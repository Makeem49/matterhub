#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.KeyVault, Az.PostgreSql
<#
.SYNOPSIS
    Rotates the MatterHub PostgreSQL password with no secret ever written to disk or logs.

.DESCRIPTION
    Runbook: docs/runbooks/secret-rotation.md. Use for scheduled rotation or immediately
    after a suspected credential leak. Steps:

      1. Pre-flight: Azure context, Key Vault and server exist, kubectl can restart the app
      2. Generate a new random password (SecureString only)
      3. Store it as a NEW version of the Key Vault secret (old version kept for audit)
      4. Set it on the PostgreSQL Flexible Server
      5. Rolling-restart the API so new pods mount the new secret through the CSI driver
      6. Wait for the rollout and confirm the readiness check (which queries the database)

    Supports -WhatIf and asks for confirmation (ConfirmImpact = High).
    Terraform does not fight this: the password is a write-only argument it never reads back.

.PARAMETER Environment
    dev or prod. Resource names are derived from the naming convention.

.EXAMPLE
    ./Invoke-DatabasePasswordRotation.ps1 -Environment dev -WhatIf

.EXAMPLE
    ./Invoke-DatabasePasswordRotation.ps1 -Environment prod -Reason "INC-1234 suspected leak"
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)] [ValidateSet('dev', 'prod')] [string] $Environment,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $Reason,
    [string] $ResourceGroupName = "rg-matterhub-$Environment",
    [string] $ServerName = "psql-matterhub-$Environment",
    [string] $KeyVaultName = "kv-matterhub-$Environment",
    [string] $SecretName = 'matterhub-db-password',
    [string] $Namespace = 'matterhub',
    [string] $Deployment = 'matterhub',
    [ValidateRange(60, 1800)] [int] $RolloutTimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MatterHubOps') -Force

function Write-Step([string] $Message) {
    Write-Information "[$(Get-Date -Format 'HH:mm:ss')] $Message" -InformationAction Continue
}

# 1. Pre-flight ----------------------------------------------------------------
$context = Get-AzContext
if (-not $context) { throw 'Not signed in to Azure. Run Connect-AzAccount first.' }
Write-Step "Azure context: $($context.Account.Id) / $($context.Subscription.Name)"

$server = Get-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $ServerName
$null = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
Write-Step "Found server $($server.Name) (state: $($server.State)) and secret $SecretName"

$canRestart = (& kubectl auth can-i patch "deployment/$Deployment" -n $Namespace 2>$null)
if ($canRestart -ne 'yes') {
    throw "kubectl cannot restart deployment/$Deployment in $Namespace. Run az aks get-credentials and kubelogin first."
}

if (-not $PSCmdlet.ShouldProcess("$ServerName and $KeyVaultName/$SecretName", 'Rotate database password')) {
    return
}

# 2-3. New password into Key Vault as a new version ------------------------------
$newPassword = New-StrongPassword -Length 32
$tags = @{ 'rotated-by' = $context.Account.Id; 'rotated-at' = (Get-Date).ToUniversalTime().ToString('o'); reason = $Reason }
$version = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $newPassword `
    -ContentType "PostgreSQL administrator password for $ServerName" -Tag $tags
Write-Step "Stored new secret version $($version.Version)"

# 4. Apply to PostgreSQL ----------------------------------------------------------
try {
    $null = Update-AzPostgreSqlFlexibleServer -ResourceGroupName $ResourceGroupName -Name $ServerName `
        -AdministratorLoginPassword $newPassword
    Write-Step 'PostgreSQL password updated'
}
catch {
    Write-Warning 'PostgreSQL update failed: Key Vault now holds a password the server does not know.'
    Write-Warning "Disable version $($version.Version) so pods keep using the previous one:"
    Write-Warning "  Update-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -Version $($version.Version) -Enable `$false"
    throw
}

# 5-6. Restart pods so they mount the new secret, then verify ----------------------
& kubectl rollout restart "deployment/$Deployment" -n $Namespace
if ($LASTEXITCODE -ne 0) { throw 'kubectl rollout restart failed' }
& kubectl rollout status "deployment/$Deployment" -n $Namespace "--timeout=$($RolloutTimeoutSeconds)s"
if ($LASTEXITCODE -ne 0) { throw 'Rollout did not complete - see docs/runbooks/secret-rotation.md (recovery section)' }

$ready = Wait-Condition -TimeoutSeconds 120 -IntervalSeconds 10 -Activity 'Readiness' -Condition {
    $pods = & kubectl get pods -n $Namespace -l 'app.kubernetes.io/component=api' -o json | ConvertFrom-Json
    $pods.items.Count -gt 0 -and -not ($pods.items | Where-Object {
            -not ($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
        })
}
if (-not $ready) { throw 'Pods are not Ready after rotation: they may be unable to connect to PostgreSQL.' }

Write-Step "Rotation complete. Reason recorded on the secret version: $Reason"
