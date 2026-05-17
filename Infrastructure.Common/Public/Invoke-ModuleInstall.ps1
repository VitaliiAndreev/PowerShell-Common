function Invoke-ModuleInstall {
    <#
    .SYNOPSIS
        Installs a module from PSGallery if absent or below the required
        minimum version, then imports it.

    .DESCRIPTION
        Centralises the install-if-missing pattern used by all infrastructure
        setup scripts. Extracting it here makes the logic testable and removes
        the need for each consumer repo to duplicate it.

        Note: this function cannot bootstrap itself. Each consumer script
        still needs a short inline guard to install Infrastructure.Common
        before this function is available - but that is a one-time cost
        per script, and all other module installs flow through this function.
        That inline guard is also responsible for ensuring the NuGet package
        provider is present, since by the time this function runs NuGet is
        already available.

    .PARAMETER ModuleName
        The name of the module to install and import.

    .PARAMETER MinimumVersion
        The minimum acceptable version. If the installed version is below
        this, the module is reinstalled. When omitted, any installed version
        is accepted and only a missing module triggers an install.

    .EXAMPLE
        Invoke-ModuleInstall -ModuleName 'Infrastructure.Secrets' `
            -MinimumVersion '1.1.0'

    .EXAMPLE
        Invoke-ModuleInstall -ModuleName 'Posh-SSH'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ModuleName,

        [Parameter()]
        [Version] $MinimumVersion
    )

    $installed = Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending | Select-Object -First 1

    # When MinimumVersion is omitted, install only if the module is absent.
    # When provided, also reinstall if the version is too old.
    $needsInstall = -not $installed -or
        ($MinimumVersion -and $installed.Version -lt $MinimumVersion)

    if ($needsInstall) {
        $versionLabel = if ($MinimumVersion) { " >= $MinimumVersion" } else { '' }
        Write-Host "Installing $ModuleName$versionLabel from PSGallery ..." `
            -ForegroundColor Cyan
        $installParams = @{
            Name        = $ModuleName
            Scope       = 'CurrentUser'
            Force       = $true
            # Required when the module exports commands that are already present
            # from a previously loaded version of the same module.
            AllowClobber = $true
        }
        if ($MinimumVersion) { $installParams.MinimumVersion = $MinimumVersion }
        Install-Module @installParams
    }

    # The version Import-Module would pick (highest on disk). Re-queried
    # after the install block so we see the freshly installed version.
    $targetVersion = (Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending | Select-Object -First 1).Version

    # Skip the unload+reload cycle when exactly the target version is
    # already the only one loaded. The unload only exists to break the
    # two-versions-live trap (older + newer both in the session at once,
    # making command resolution order-dependent); when that trap is not
    # in play, reloading is wasted work.
    $loaded = @(Get-Module -Name $ModuleName)
    $alreadyCorrect = $loaded.Count -eq 1 -and
                      $loaded[0].Version -eq $targetVersion
    if (-not $alreadyCorrect) {
        if ($loaded) { $loaded | Remove-Module -Force }
        Import-Module $ModuleName -Force -ErrorAction Stop
    }
}
