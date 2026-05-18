@{
    ModuleVersion        = '4.1.0'
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
        # Top-level utilities
        'Assert-RequiredProperties',
        'ConvertTo-Array',
        'Invoke-ModuleInstall',
        # Retry loop (Public/Retry/)
        'Invoke-WithNetworkRetry',
        'Invoke-WithRetry',
        # Transient-error strategies (Public/Retry/TransientErrorStrategies/)
        'New-FileLockRetryStrategy',
        'New-TransientNetworkRetryStrategy',
        # Backoff strategies (Public/Retry/BackoffStrategies/)
        'New-ConstantBackoffStrategy',
        'New-CustomBackoffStrategy',
        'New-ExponentialBackoffStrategy',
        'New-LinearBackoffStrategy'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
}
