BeforeAll {
    # Dot-source the Public file directly so both the exported
    # Invoke-WithNetworkRetry and the file-private Test-TransientNetworkException
    # land in test scope - in module form Test-TransientNetworkException is
    # not exported, but at the file level it is just another function.
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Invoke-WithNetworkRetry.ps1"

    # Hand-rolled ErrorRecord factory. Pester's ParameterFilter cannot
    # synthesise ErrorRecords for us, and we need the exception chain to
    # walk through specific types for Test-TransientNetworkException.
    function New-TestErrorRecord {
        param([Exception] $Exception)
        return [System.Management.Automation.ErrorRecord]::new(
            $Exception, 'TestError', 'NotSpecified', $null)
    }

    # Builds a fake HttpResponseException-shaped object. The real type lives
    # in Microsoft.PowerShell.Commands and is awkward to construct directly,
    # so we mimic its surface (GetType().FullName, Response.StatusCode)
    # using Add-Type once per test run - Test-TransientNetworkException
    # inspects only those two members.
    function New-FakeHttpResponseException {
        param([int] $StatusCode)
        Add-Type -TypeDefinition @"
namespace Microsoft.PowerShell.Commands {
    public class HttpResponseException : System.Exception {
        public object Response { get; set; }
        public HttpResponseException(string message, object response) : base(message) {
            Response = response;
        }
    }
}
"@ -ErrorAction SilentlyContinue
        $response = [PSCustomObject]@{ StatusCode = $StatusCode }
        return [Microsoft.PowerShell.Commands.HttpResponseException]::new('err', $response)
    }
}

Describe 'Test-TransientNetworkException' {

    It 'returns true for HttpRequestException (DNS / connect failure)' {
        $inner = [System.Net.Sockets.SocketException]::new()
        $ex    = [System.Net.Http.HttpRequestException]::new('dns', $inner)
        $rec   = New-TestErrorRecord -Exception $ex

        Test-TransientNetworkException -ErrorRecord $rec | Should -BeTrue
    }

    It 'returns true for a nested SocketException only reachable via InnerException' {
        # The wrapper (Exception) is a vanilla System.Exception - not on the
        # transient list. The walker must descend into InnerException to find
        # the SocketException underneath.
        $inner = [System.Net.Sockets.SocketException]::new()
        $outer = [Exception]::new('wrapped', $inner)
        $rec   = New-TestErrorRecord -Exception $outer

        Test-TransientNetworkException -ErrorRecord $rec | Should -BeTrue
    }

    It 'returns true for a 5xx HttpResponseException (server error)' {
        $ex  = New-FakeHttpResponseException -StatusCode 503
        $rec = New-TestErrorRecord -Exception $ex

        Test-TransientNetworkException -ErrorRecord $rec | Should -BeTrue
    }

    It 'returns false for a 4xx HttpResponseException (client error)' {
        # Client errors are permanent - retrying a 404 will keep producing 404.
        $ex  = New-FakeHttpResponseException -StatusCode 404
        $rec = New-TestErrorRecord -Exception $ex

        Test-TransientNetworkException -ErrorRecord $rec | Should -BeFalse
    }

    It 'returns false for a non-network exception (string throw / RuntimeException)' {
        # Mocks elsewhere throw plain strings; the retry layer must not
        # incur delays on those.
        $ex  = [System.Management.Automation.RuntimeException]::new('boom')
        $rec = New-TestErrorRecord -Exception $ex

        Test-TransientNetworkException -ErrorRecord $rec | Should -BeFalse
    }
}

Describe 'Invoke-WithNetworkRetry' {

    It 'returns the script block result on first-attempt success' {
        $script:_callCount = 0
        $result = Invoke-WithNetworkRetry -ScriptBlock {
            $script:_callCount++
            return 'ok'
        }

        $result            | Should -Be 'ok'
        $script:_callCount | Should -Be 1
    }

    It 'retries a transient failure and returns the eventual success' {
        $script:_attempts = 0
        $result = Invoke-WithNetworkRetry `
            -InitialDelaySeconds 0 `
            -ScriptBlock {
                $script:_attempts++
                if ($script:_attempts -lt 3) {
                    throw [System.Net.Http.HttpRequestException]::new('dns')
                }
                return 'finally'
            }

        $result            | Should -Be 'finally'
        $script:_attempts  | Should -Be 3
    }

    It 'propagates a permanent failure immediately without retrying' {
        # A plain string throw is non-transient. Test runs in well under
        # 1 second; if the helper retried, the default 2s delay would
        # blow that budget.
        $script:_count = 0
        { Invoke-WithNetworkRetry -ScriptBlock {
            $script:_count++
            throw 'permanent'
        } } | Should -Throw

        $script:_count | Should -Be 1
    }

    It 'gives up after MaxAttempts transient failures and rethrows the underlying error' {
        $script:_tries = 0
        { Invoke-WithNetworkRetry `
              -MaxAttempts 3 `
              -InitialDelaySeconds 0 `
              -ScriptBlock {
                  $script:_tries++
                  throw [System.Net.Http.HttpRequestException]::new('dns')
              }
        } | Should -Throw

        $script:_tries | Should -Be 3
    }
}
