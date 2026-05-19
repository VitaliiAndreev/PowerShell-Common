BeforeAll {
    # Invoke-ModuleInstall now depends on the retry primitives + strategy
    # factories (used at runtime via dynamic lookup, so the missing
    # dot-source only surfaces when the install path actually executes -
    # i.e. the absent-module test, not the already-installed one).
    . "$PSScriptRoot\..\..\Infrastructure.Common\Private\Retry\Assert-RetryStrategyShape.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\Invoke-WithRetry.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientPowerShellModuleInstallRetryStrategy.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Invoke-ModuleInstall.ps1"
}

Describe 'Invoke-ModuleInstall' -Tag 'Integration' {

    It 'installs an absent module and makes it importable' {
        # Microsoft.PowerShell.SecretManagement is not pre-installed in the
        # base mcr.microsoft.com/powershell container image, making it a
        # reliable absent-module test case. The workflow installs only Pester
        # before running this file.
        $moduleName = 'Microsoft.PowerShell.SecretManagement'
        Remove-Module $moduleName -ErrorAction SilentlyContinue

        Invoke-ModuleInstall -ModuleName $moduleName

        Get-Module -Name $moduleName | Should -Not -BeNullOrEmpty
    }

    It 'does not reinstall a module that already meets the minimum version' {
        # Pester is always present in the test environment. Use it as a
        # reliable already-installed subject. Verify no new version appears
        # after the call (i.e. Install-Module was not invoked).
        $before = (Get-Module -ListAvailable -Name Pester |
            Sort-Object Version -Descending | Select-Object -First 1).Version

        Invoke-ModuleInstall -ModuleName 'Pester' -MinimumVersion '5.0'

        $after = (Get-Module -ListAvailable -Name Pester |
            Sort-Object Version -Descending | Select-Object -First 1).Version

        $after | Should -Be $before
    }
}
