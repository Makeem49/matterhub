#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources
<#
.SYNOPSIS
    Audits Azure resources for the governance tags MatterHub requires.

.DESCRIPTION
    Lists every resource in the given resource groups, reports which ones are missing
    required tags (used for cost allocation, data classification and ownership), and can
    fail a pipeline when anything is non-compliant. Azure Policy blocks untagged resource
    groups; this script catches untagged *resources* and gives a readable report.

.PARAMETER ResourceGroupName
    One or more resource groups to audit.

.PARAMETER RequiredTag
    Tag names every resource must carry (case-insensitive).

.PARAMETER OutputPath
    Optional CSV report path.

.PARAMETER FailOnNonCompliant
    Exit with code 1 when any resource is non-compliant (for pipelines).

.EXAMPLE
    ./Test-TagCompliance.ps1 -ResourceGroupName rg-matterhub-dev, rg-matterhub-prod -OutputPath tags.csv

.EXAMPLE
    ./Test-TagCompliance.ps1 -ResourceGroupName rg-matterhub-prod -FailOnNonCompliant
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string[]] $ResourceGroupName,
    [string[]] $RequiredTag = @('service', 'environment', 'managed-by', 'data-classification'),
    [string] $OutputPath,
    [switch] $FailOnNonCompliant
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MatterHubOps') -Force

if (-not (Get-AzContext)) { throw 'Not signed in to Azure. Run Connect-AzAccount first.' }

$resources = foreach ($rg in $ResourceGroupName) {
    Write-Verbose "Listing resources in $rg"
    Get-AzResource -ResourceGroupName $rg
}

$report = @(Get-TagComplianceReport -Resource @($resources) -RequiredTag $RequiredTag)
$nonCompliant = @($report | Where-Object { -not $_.Compliant })

$report | Sort-Object Compliant, ResourceType, Name |
    Format-Table Name, ResourceType, ResourceGroupName, Compliant, MissingTags -AutoSize | Out-Host

if ($OutputPath) {
    $report | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Information "Report written to $OutputPath" -InformationAction Continue
}

Write-Information ("{0} of {1} resources compliant" -f ($report.Count - $nonCompliant.Count), $report.Count) -InformationAction Continue

if ($FailOnNonCompliant -and $nonCompliant.Count -gt 0) {
    Write-Error "$($nonCompliant.Count) resource(s) are missing required tags" -ErrorAction Continue
    exit 1
}
