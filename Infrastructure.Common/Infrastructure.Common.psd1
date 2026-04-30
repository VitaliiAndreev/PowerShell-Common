@{
    ModuleVersion        = '2.0.1'
    GUID                 = 'b7d3f2a1-4c9e-4f8d-a2b5-3e6d7f8a9b0c'
    Author               = 'Vitaly Andrev'
    Description          = 'Shared PowerShell utilities for infrastructure repos.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')
    RootModule        = 'Infrastructure.Common.psm1'
    # FunctionsToExport is module discovery metadata: used by
    # Get-Module -ListAvailable, Find-Module, and PSGallery without loading
    # the module. It does NOT control what is callable at runtime - that is
    # governed by Export-ModuleMember in the psm1, which takes precedence.
    # Both lists must stay in sync. The shared Module.Tests.ps1 in the
    # run-unit-tests action enforces this.
    FunctionsToExport = @(
        'Assert-RequiredProperties',
        'ConvertTo-Array',
        'Get-GitHubAppToken',
        'Get-PendingDeployment',
        'Invoke-GitHubApi',
        'Invoke-ModuleInstall',
        'Invoke-SshClientCommand',
        'Set-DeploymentStatus'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
