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

    # Retry policy is an implementation detail of the install step, not a
    # caller-facing concern - every consumer wants the same "ride out a
    # PSGallery blip" behaviour. Six attempts with 10 s -> 20 -> 40 -> 80
    # -> 160 (capped at 300 s) gives roughly 5 min of total wait before a
    # hard failure: long enough to clear a transient resolution issue,
    # short enough that a real outage fails the run.
    $installMaxAttempts         = 6
    $installInitialDelaySeconds = 10
    $installMaxDelaySeconds     = 300

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
            # Promote PSGallery resolution failures from non-terminating
            # warnings to terminating errors so Invoke-WithRetry's try/catch
            # sees them. Without this, the install silently no-ops and
            # consumers fall through to whatever stale version is cached.
            ErrorAction = 'Stop'
        }
        if ($MinimumVersion) { $installParams.MinimumVersion = $MinimumVersion }

        # Wrap the install in Invoke-WithRetry so transient PSGallery blips
        # (the "Unable to resolve package source" failure mode) do not bring
        # down a provision run. Two strategies are OR-composed:
        #   - TransientPowerShellModuleInstall: PSGallery-specific source-
        #     resolution patterns ("Unable to resolve package source", ...)
        #   - TransientNetwork: generic transient network failures, with a
        #     message-based fallback path for cases where PowerShellGet has
        #     wrapped the underlying typed exception (DNS, timeout, 5xx).
        # Permanent failures (typos, missing publisher signature, auth)
        # match neither and propagate immediately so they fail fast instead
        # of stalling for the full retry budget.
        #
        # The scriptblock captures the warning stream because PSGallery
        # source-resolution failure surfaces as a WARNING ("Unable to
        # resolve package source ...") followed by a generic terminating
        # error ("No match was found ..."). "No match was found" alone is
        # also what a genuine typo produces, so this block promotes the
        # warning text into the error message so the transient case still
        # matches a pattern even though the underlying error text is
        # ambiguous on its own.
        Invoke-WithRetry `
            -OperationName   "Install-Module $ModuleName" `
            -RetryStrategy   @(
                (New-TransientPowerShellModuleInstallRetryStrategy),
                (New-TransientNetworkRetryStrategy)
            ) `
            -BackoffStrategy (New-ExponentialBackoffStrategy `
                -InitialDelaySeconds $installInitialDelaySeconds `
                -MaxIntervalSeconds  $installMaxDelaySeconds) `
            -MaxAttempts     $installMaxAttempts `
            -ScriptBlock     {
                $installWarnings = $null
                try {
                    Install-Module @installParams `
                        -WarningVariable installWarnings
                }
                catch {
                    # $_ here is the terminating error from Install-Module
                    # (terminating because installParams includes
                    # ErrorAction=Stop). $installWarnings is parallel
                    # context captured from the warning stream during the
                    # same call - we inspect it to decide whether to
                    # enrich $_ before rethrowing.
                    $sourceWarning = $null
                    if ($installWarnings) {
                        $sourceWarning = $installWarnings | Where-Object {
                            Test-PSGallerySourceResolutionMessage `
                                -Message $_.Message
                        } | Select-Object -First 1
                    }
                    if ($sourceWarning) {
                        # Wrap so the strategy sees a transient pattern,
                        # but preserve the original ErrorRecord as an
                        # InnerException so operators can still see the
                        # underlying "No match was found" text.
                        #
                        # Note: this block already decided the failure is
                        # transient (Test-PSGallerySourceResolutionMessage
                        # matched a warning), and the strategy will
                        # re-run the same check on the enriched error
                        # text below. That second check is intentional
                        # defensive belt-and-braces - see the header
                        # comment on Test-PSGallerySourceResolutionMessage
                        # in New-TransientPowerShellModuleInstallRetryStrategy.ps1.
                        throw [System.Exception]::new(
                            ("$($_.Exception.Message) " +
                             "(caused by: $($sourceWarning.Message))"),
                            $_.Exception)
                    }
                    throw
                }
            }
    }

    # The version Import-Module would pick (highest on disk). Re-queried
    # after the install block so we see the freshly installed version.
    # Property accessed via an intermediate variable so Set-StrictMode
    # does not blow up when the module is genuinely absent (e.g. in unit
    # tests where Install-Module is mocked and installs nothing).
    $highestAvailable = Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending | Select-Object -First 1
    $targetVersion = if ($highestAvailable) { $highestAvailable.Version } else { $null }

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
