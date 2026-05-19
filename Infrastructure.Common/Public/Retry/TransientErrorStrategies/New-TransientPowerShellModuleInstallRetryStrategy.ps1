<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. The public surface is
    New-TransientPowerShellModuleInstallRetryStrategy; Test-TransientPowerShellModuleInstallException
    is a file-private helper kept alongside the factory so the
    classification policy lives next to its sole consumer.
#>

# ---------------------------------------------------------------------------
# Test-TransientPowerShellModuleInstallException (private)
#   Returns $true when an Install-Module / Install-Package failure looks
#   like a transient PSGallery-specific issue (source resolution).
#   Generic transient network failures (DNS, timeout, 5xx) are out of
#   scope here - they are handled by New-TransientNetworkRetryStrategy's
#   message-based fallback path, OR-composed by callers that face the
#   wrapped-exception problem (see Invoke-ModuleInstall).
#
#   Classification is by message pattern because PowerShellGet wraps
#   its underlying failures in generic exception types. The pattern
#   list will need occasional refresh as PowerShellGet wording shifts -
#   the cost of a missed pattern is a real config error masked as
#   transient and retried for the full attempt budget (~5 min) before
#   failing, which is the wrong direction to err in. So keep the list
#   narrow and aimed at observed flake modes.
#
#   Why not match the broad "No match was found" string: it is also what
#   Install-Module emits for a genuine typo. Treating it as transient
#   would make every misspelt module name wait 5 min before failing.
#   Invoke-ModuleInstall's call site promotes the *warning-stream* source-
#   resolution message into the error text so the truly-transient case
#   still matches one of the patterns below even when the terminating
#   error itself says only "No match was found".
# ---------------------------------------------------------------------------

# Single source of truth for PSGallery source-resolution patterns.
# Two consumers feed strings into this helper:
#   1. Test-TransientPowerShellModuleInstallException below, against the
#      combined ErrorRecord message text.
#   2. Invoke-ModuleInstall, against each captured warning's .Message
#      so it can decide whether to promote the warning into the error
#      message before rethrowing.
# Keeping the pattern list in one place prevents the two consumers from
# drifting out of sync as PowerShellGet wording shifts.
#
# Why two consumers - one signal arrives via two channels:
#   Today, PowerShellGet emits the source-resolution text only in the
#   warning stream; the terminating error itself is the ambiguous
#   "No match was found". So in practice consumer #2 (warning check in
#   Invoke-ModuleInstall) is what catches the actual flake, and #1 (the
#   strategy's check against the error text) only matches because #2
#   first promoted the warning text into the error.
#
#   The strategy's re-check is therefore *defensive belt-and-braces*: if
#   a future PowerShellGet version starts surfacing source-resolution
#   text directly in the terminating error (skipping the warning stream),
#   the strategy still classifies it correctly without any change to
#   Invoke-ModuleInstall. Cost is one extra regex evaluation per failed
#   attempt - negligible compared to the retry sleep budget.
function Test-PSGallerySourceResolutionMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Message
    )

    $transientPatterns = @(
        'Unable to resolve package source',
        'package source.*(unavailable|not\s+available|not\s+found)'
    )

    foreach ($pattern in $transientPatterns) {
        if ($Message -match $pattern) { return $true }
    }
    return $false
}

function Test-TransientPowerShellModuleInstallException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    # Both Exception.Message and ErrorDetails.Message are checked because
    # PowerShellGet sometimes populates only the latter (the operator-
    # facing text) while leaving Exception.Message as a generic wrapper.
    $messages = @()
    if ($ErrorRecord.Exception)    { $messages += $ErrorRecord.Exception.Message }
    if ($ErrorRecord.ErrorDetails) { $messages += $ErrorRecord.ErrorDetails.Message }
    $combined = ($messages -join ' ')

    return (Test-PSGallerySourceResolutionMessage -Message $combined)
}

function New-TransientPowerShellModuleInstallRetryStrategy {
    <#
    .SYNOPSIS
        Builds a retry strategy hashtable that matches transient
        PSGallery-specific failures (source resolution) emitted by
        Install-Module / Install-Package. Generic network failures
        (DNS, timeout, 5xx) are handled by New-TransientNetworkRetryStrategy
        and should be OR-composed alongside this strategy.

    .DESCRIPTION
        Returned shape is the standard retry-strategy contract consumed by
        Invoke-WithRetry:

            @{
                Name        = 'TransientPowerShellModuleInstall'
                ShouldRetry = { param($err) <bool> }
            }

        Scope is intentionally PSGallery-only (see file header for the
        rationale). Permanent failures (typos, publisher-signature
        mismatches, auth) propagate immediately.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock   { Install-Module Foo -ErrorAction Stop } `
            -RetryStrategy @(
                (New-TransientPowerShellModuleInstallRetryStrategy),
                (New-TransientNetworkRetryStrategy)
            ) `
            -MaxAttempts   6
    #>
    [CmdletBinding()]
    param()

    return @{
        Name        = 'TransientPowerShellModuleInstall'
        ShouldRetry = {
            param([System.Management.Automation.ErrorRecord] $ErrorRecord)
            Test-TransientPowerShellModuleInstallException -ErrorRecord $ErrorRecord
        }
    }
}
