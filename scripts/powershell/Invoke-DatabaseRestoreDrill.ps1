#Requires -Version 7.2
<#
.SYNOPSIS
    Disaster-recovery drill: restores the MatterHub database and measures RTO and RPO.

.DESCRIPTION
    Backups are only proven by restoring them. This drill restores the PostgreSQL Flexible
    Server to a new server, either:

      PointInTime  - same region, to a chosen moment (e.g. before a bad migration)
      Geo          - into the paired region (UK West) from geo-redundant backups, the
                     procedure used if UK South is unavailable

    It times the restore, checks the restored server is Ready and holds the application
    database, writes a markdown evidence report (docs/disaster-recovery.md asks for one
    per quarter), and deletes the drill server unless -KeepServer is given.

.EXAMPLE
    ./Invoke-DatabaseRestoreDrill.ps1 -Environment prod -Mode PointInTime -ReportPath drill.md

.EXAMPLE
    ./Invoke-DatabaseRestoreDrill.ps1 -Environment prod -Mode Geo `
        -TargetSubnetId $drSubnet -TargetPrivateDnsZoneId $drZone -ReportPath geo-drill.md
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidateSet('dev', 'prod')] [string] $Environment,
    [ValidateSet('PointInTime', 'Geo')] [string] $Mode = 'PointInTime',
    [datetime] $RestorePoint = (Get-Date).ToUniversalTime().AddMinutes(-15),
    [string] $ResourceGroupName = "rg-matterhub-$Environment",
    [string] $SourceServerName = "psql-matterhub-$Environment",
    [string] $TargetServerName = "psql-matterhub-$Environment-drill-$((Get-Date).ToUniversalTime().ToString('MMddHHmm'))",
    [string] $TargetLocation = 'ukwest',
    [string] $TargetSubnetId,
    [string] $TargetPrivateDnsZoneId,
    [string] $DatabaseName = 'matterhub',
    [int] $RtoTargetMinutes = 60,
    [int] $RpoTargetMinutes = 15,
    [string] $ReportPath = "restore-drill-$Environment-$((Get-Date).ToString('yyyyMMdd-HHmm')).md",
    [switch] $KeepServer
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MatterHubOps') -Force

if ($Mode -eq 'Geo' -and (-not $TargetSubnetId -or -not $TargetPrivateDnsZoneId)) {
    throw 'Geo restore of a private (VNet-integrated) server needs -TargetSubnetId and -TargetPrivateDnsZoneId in the target region.'
}

$source = Invoke-AzCli postgres flexible-server show -g $ResourceGroupName -n $SourceServerName
Write-Information "Source: $($source.name) in $($source.location), geo-redundant backup: $($source.backup.geoRedundantBackup)" -InformationAction Continue
if ($Mode -eq 'Geo' -and $source.backup.geoRedundantBackup -ne 'Enabled') {
    throw 'Geo-redundant backup is not enabled on the source server; geo-restore is impossible.'
}

if (-not $PSCmdlet.ShouldProcess($TargetServerName, "$Mode restore of $SourceServerName")) { return }

$startedAt = (Get-Date).ToUniversalTime()
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$notes = [System.Collections.Generic.List[string]]::new()

if ($Mode -eq 'PointInTime') {
    $null = Invoke-AzCli postgres flexible-server restore -g $ResourceGroupName -n $TargetServerName `
        --source-server $source.id --restore-time $RestorePoint.ToString('o')
}
else {
    $null = Invoke-AzCli postgres flexible-server geo-restore -g $ResourceGroupName -n $TargetServerName `
        --source-server $source.id --location $TargetLocation `
        --subnet $TargetSubnetId --private-dns-zone $TargetPrivateDnsZoneId
    # Geo-restore restores the latest geo-replicated backup, not an arbitrary point.
    $RestorePoint = [datetime]$source.backup.earliestRestoreDate
    $notes.Add('Geo-restore uses the most recent geo-replicated backup; RPO reflects replication lag (typically < 1 h).')
}

$ready = Wait-Condition -TimeoutSeconds ($RtoTargetMinutes * 120) -IntervalSeconds 30 -Activity 'Restore' -Condition {
    (Invoke-AzCli postgres flexible-server show -g $ResourceGroupName -n $TargetServerName).state -eq 'Ready'
}
$timer.Stop()

$validation = $false
if ($ready) {
    $db = Invoke-AzCli postgres flexible-server db show -g $ResourceGroupName -s $TargetServerName -d $DatabaseName
    $validation = $null -ne $db
    $notes.Add("Database '$DatabaseName' present on restored server: $validation.")
    $notes.Add('Application-level checks (row counts, latest audit event) run from a pod in the VNet: see docs/disaster-recovery.md.')
}
else {
    $notes.Add('Restored server did not reach Ready within twice the RTO target.')
}

$report = Get-RestoreDrillReport -Environment $Environment -Mode $Mode -SourceServer $SourceServerName `
    -RestoredServer $TargetServerName -RestorePoint $RestorePoint -StartedAt $startedAt -Duration $timer.Elapsed `
    -RtoTargetMinutes $RtoTargetMinutes -RpoTargetMinutes $RpoTargetMinutes -ValidationPassed $validation -Notes $notes
Set-Content -Path $ReportPath -Value $report -Encoding utf8
Write-Information $report -InformationAction Continue

if (-not $KeepServer -and $PSCmdlet.ShouldProcess($TargetServerName, 'Delete drill server')) {
    $null = Invoke-AzCli postgres flexible-server delete -g $ResourceGroupName -n $TargetServerName --yes
    Write-Information "Deleted drill server $TargetServerName" -InformationAction Continue
}
