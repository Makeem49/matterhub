@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Scripts report progress with Write-Information/Out-Host deliberately.
        'PSAvoidUsingWriteHost'
    )
}
