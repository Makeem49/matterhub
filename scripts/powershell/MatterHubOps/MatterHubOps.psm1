#Requires -Version 7.2
<#
    Shared functions for MatterHub operational scripts. Pure functions are kept free of
    Azure calls so they can be unit-tested with Pester (see ../tests).
#>
Set-StrictMode -Version Latest

function Get-TagComplianceReport {
    <#
    .SYNOPSIS
        Compares resources' tags against a list of required tag names.
    .OUTPUTS
        One object per resource: Name, ResourceType, ResourceGroupName, Compliant, MissingTags.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Resource,
        [Parameter(Mandatory)] [string[]] $RequiredTag
    )

    foreach ($item in $Resource) {
        $tags = @{}
        if ($null -ne $item.Tags) {
            foreach ($key in $item.Tags.Keys) { $tags[$key.ToLowerInvariant()] = $item.Tags[$key] }
        }
        $missing = @(
            $RequiredTag | Where-Object {
                -not $tags.ContainsKey($_.ToLowerInvariant()) -or
                [string]::IsNullOrWhiteSpace([string]$tags[$_.ToLowerInvariant()])
            }
        )
        [pscustomobject]@{
            Name              = $item.Name
            ResourceType      = $item.ResourceType
            ResourceGroupName = $item.ResourceGroupName
            Compliant         = ($missing.Count -eq 0)
            MissingTags       = ($missing -join ', ')
        }
    }
}

function New-StrongPassword {
    <#
    .SYNOPSIS
        Cryptographically random password containing upper, lower, digit and safe symbols.
        Symbols are limited to ones that need no escaping in connection strings or URLs.
        The password is built straight into a SecureString; a plain string exists only
        when -AsPlainText is requested (tests).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Creates an in-memory value only; changes no system state.')]
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [ValidateRange(16, 128)] [int] $Length = 32,
        [switch] $AsPlainText
    )

    $sets = @(
        'ABCDEFGHJKLMNPQRSTUVWXYZ',   # no I/O (ambiguous)
        'abcdefghijkmnopqrstuvwxyz',  # no l
        '23456789',                   # no 0/1
        '-_.~'
    )
    $all = -join $sets
    $chars = [System.Collections.Generic.List[char]]::new()
    foreach ($set in $sets) { $chars.Add($set[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($set.Length)]) }
    while ($chars.Count -lt $Length) {
        $chars.Add($all[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($all.Length)])
    }
    # Fisher-Yates shuffle so the guaranteed characters are not always first.
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }
    if ($AsPlainText) { return (-join $chars) }
    $secure = [securestring]::new()
    foreach ($c in $chars) { $secure.AppendChar($c) }
    $chars.Clear()
    $secure.MakeReadOnly()
    return $secure
}

function Wait-Condition {
    <#
    .SYNOPSIS
        Polls a script block until it returns $true or the timeout expires.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [scriptblock] $Condition,
        [ValidateRange(1, 86400)] [int] $TimeoutSeconds = 600,
        [ValidateRange(1, 3600)] [int] $IntervalSeconds = 15,
        [string] $Activity = 'Waiting'
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) { return $true }
        Write-Verbose "$Activity - not ready, retrying in $IntervalSeconds s"
        Start-Sleep -Seconds $IntervalSeconds
    }
    return $false
}

function Invoke-AzCli {
    <#
    .SYNOPSIS
        Runs an Azure CLI command, returns parsed JSON, and throws on failure.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Arguments)

    $output = & az @Arguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Arguments -join ' ') failed (exit $LASTEXITCODE): $output"
    }
    $text = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

function Get-RestoreDrillReport {
    <#
    .SYNOPSIS
        Builds the markdown evidence record for a database restore drill.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string] $Environment,
        [Parameter(Mandatory)] [ValidateSet('PointInTime', 'Geo')] [string] $Mode,
        [Parameter(Mandatory)] [string] $SourceServer,
        [Parameter(Mandatory)] [string] $RestoredServer,
        [Parameter(Mandatory)] [datetime] $RestorePoint,
        [Parameter(Mandatory)] [datetime] $StartedAt,
        [Parameter(Mandatory)] [timespan] $Duration,
        [Parameter(Mandatory)] [int] $RtoTargetMinutes,
        [Parameter(Mandatory)] [int] $RpoTargetMinutes,
        [Parameter(Mandatory)] [bool] $ValidationPassed,
        [string[]] $Notes = @()
    )

    $rpo = $StartedAt.ToUniversalTime() - $RestorePoint.ToUniversalTime()
    $rtoMet = $Duration.TotalMinutes -le $RtoTargetMinutes
    $rpoMet = $rpo.TotalMinutes -le $RpoTargetMinutes
    $verdict = if ($rtoMet -and $rpoMet -and $ValidationPassed) { 'PASS' } else { 'FAIL' }
    $yesNo = { param($b) if ($b) { 'yes' } else { 'no' } }

    $lines = @(
        "# Database restore drill - $Environment - $verdict",
        '',
        '| Item | Value |',
        '|---|---|',
        "| Date (UTC) | $($StartedAt.ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) |",
        "| Mode | $Mode |",
        "| Source server | $SourceServer |",
        "| Restored server | $RestoredServer |",
        "| Restore point (UTC) | $($RestorePoint.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) |",
        "| Time to restore (RTO) | $([math]::Round($Duration.TotalMinutes, 1)) min (target $RtoTargetMinutes, met: $(& $yesNo $rtoMet)) |",
        "| Data-loss window (RPO) | $([math]::Round($rpo.TotalMinutes, 1)) min (target $RpoTargetMinutes, met: $(& $yesNo $rpoMet)) |",
        "| Validation | $(if ($ValidationPassed) { 'passed' } else { 'FAILED' }) |",
        ''
    )
    if ($Notes.Count -gt 0) {
        $lines += '## Notes'
        $lines += ($Notes | ForEach-Object { "- $_" })
    }
    return ($lines -join [Environment]::NewLine)
}

Export-ModuleMember -Function Get-TagComplianceReport, New-StrongPassword, Wait-Condition, Invoke-AzCli, Get-RestoreDrillReport
