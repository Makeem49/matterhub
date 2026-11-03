@{
    RootModule        = 'MatterHubOps.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '6f1d2c1e-8a3b-4b8e-9d64-2b8f0c6a7e51'
    Author            = 'Akeem Moshood'
    Description       = 'Operational automation for the MatterHub platform on Azure.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-TagComplianceReport',
        'New-StrongPassword',
        'Wait-Condition',
        'Invoke-AzCli',
        'Get-RestoreDrillReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
