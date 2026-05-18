<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. The public surface is
    New-TransientNetworkRetryStrategy; Test-TransientNetworkException is a
    file-private helper kept alongside the factory so the classification
    policy lives next to its sole consumer.
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
#   policy decision through the strategy factory is enough, and keeping
#   it private leaves room to evolve the classification without breaking
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

function New-TransientNetworkRetryStrategy {
    <#
    .SYNOPSIS
        Builds a retry strategy hashtable that matches transient network
        failures (DNS hiccups, dropped connections, 5xx responses,
        HttpClient timeouts).

    .DESCRIPTION
        Returned shape is the standard retry-strategy contract consumed by
        Invoke-WithRetry:

            @{
                Name        = 'TransientNetwork'
                ShouldRetry = { param($err) <bool> }
            }

        The ShouldRetry predicate delegates to the file-private
        Test-TransientNetworkException helper, which walks the exception
        chain. 4xx HttpResponseExceptions and non-network errors are
        classified as permanent so the caller fails fast instead of
        sleeping through retries that cannot succeed.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock   { Invoke-RestMethod $url } `
            -RetryStrategy (New-TransientNetworkRetryStrategy)
    #>
    [CmdletBinding()]
    param()

    return @{
        Name        = 'TransientNetwork'
        ShouldRetry = {
            param([System.Management.Automation.ErrorRecord] $ErrorRecord)
            Test-TransientNetworkException -ErrorRecord $ErrorRecord
        }
    }
}
