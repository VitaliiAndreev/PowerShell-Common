<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. The public surface is
    Invoke-WithNetworkRetry; Test-TransientNetworkException is a private
    helper kept in this file so the classification policy lives next to
    the retry loop that consumes it.
#>

# ---------------------------------------------------------------------------
# Test-TransientNetworkException (private)
#   Walks the exception chain on an ErrorRecord and decides whether the
#   failure is a transient network condition (worth retrying) or a
#   permanent error (a 4xx client response, an argument bug, the mock
#   layer in tests throwing a plain string, etc.).
#
#   Transient signals:
#     - System.Net.Http.HttpRequestException   (DNS, connection refused,
#                                               socket errors, generic
#                                               HttpClient failures)
#     - System.Net.WebException                (legacy WebClient stack)
#     - System.Net.Sockets.SocketException     (raw socket errors -
#                                               "No such host is known")
#     - System.TimeoutException
#     - System.Threading.Tasks.TaskCanceledException (HttpClient timeout)
#
#   HTTP status-code rule:
#     - 5xx server errors -> transient, retry.
#     - 4xx client errors -> permanent, fail fast.
#
#   Anything else (e.g. ArgumentException, RuntimeException from a
#   string throw in tests) is treated as permanent so a bug or a test
#   mock does not incur retry delays.
#
#   Kept module-internal (not in Export-ModuleMember) - exposing the
#   policy decision through the retry wrapper is enough, and keeping it
#   private leaves room to evolve the classification without breaking
#   callers.
# ---------------------------------------------------------------------------

function Test-TransientNetworkException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $transientTypeNames = @(
        'System.Net.Http.HttpRequestException',
        'System.Net.WebException',
        'System.Net.Sockets.SocketException',
        'System.TimeoutException',
        'System.Threading.Tasks.TaskCanceledException'
    )

    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        $typeName = $ex.GetType().FullName

        # PowerShell 7's Invoke-RestMethod / Invoke-WebRequest emit
        # HttpResponseException for non-success responses. Distinguish 4xx
        # (permanent) from 5xx (transient) by the Response.StatusCode value.
        if ($typeName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $statusCode = [int] $ex.Response.StatusCode
            return ($statusCode -ge 500)
        }

        if ($transientTypeNames -contains $typeName) {
            return $true
        }

        $ex = $ex.InnerException
    }

    return $false
}

# ---------------------------------------------------------------------------
# Invoke-WithNetworkRetry
#   Runs $ScriptBlock and retries on transient network failures with
#   exponential backoff. Non-transient failures (4xx, validation errors,
#   mock-thrown strings in tests) propagate immediately so the operator
#   gets a fast, actionable error instead of waiting through retries
#   that cannot succeed.
#
#   Default policy: 3 attempts total, delays of 2s and 4s between them.
#   That covers brief DNS hiccups and short-lived connectivity drops
#   without making a hard failure feel sluggish.
#
#   Parameter override is provided so callers (and tests) can tighten
#   or loosen the policy. The helper is intentionally tiny and stateless;
#   any larger retry strategy (circuit breaker, jitter) belongs in a
#   dedicated module, not here.
# ---------------------------------------------------------------------------

function Invoke-WithNetworkRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        # Surfaced in the warning so the operator can tell which call is
        # being retried (e.g. "Adoptium API lookup" vs "tarball download").
        [string] $OperationName = 'network call',

        # Total attempts including the first try. 1 disables retry entirely
        # (useful in tests where the failure is deterministic).
        [int] $MaxAttempts = 3,

        # Seconds to wait before the first retry. Doubles each subsequent
        # attempt. 2 -> 4 -> 8 ... bounded by the attempt count above.
        [int] $InitialDelaySeconds = 2
    )

    $delay = $InitialDelaySeconds
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            # Permanent errors (4xx, mocks, argument bugs) skip retry so
            # callers see the original failure without added latency.
            if (-not (Test-TransientNetworkException -ErrorRecord $_)) {
                throw
            }

            # Last attempt - propagate so the caller sees the underlying
            # network error rather than a generic "gave up" wrapper.
            if ($attempt -ge $MaxAttempts) {
                throw
            }

            Write-Warning (
                "$OperationName failed (attempt $attempt/$MaxAttempts): " +
                "$($_.Exception.Message). Retrying in ${delay}s ..."
            )
            Start-Sleep -Seconds $delay
            $delay *= 2
        }
    }
}
