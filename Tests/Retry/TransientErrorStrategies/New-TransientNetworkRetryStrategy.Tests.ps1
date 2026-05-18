BeforeAll {
    # Dot-source the Public file directly so both the exported factory and
    # the file-private Test-TransientNetworkException land in test scope.
    # At the file level Test-TransientNetworkException is just another
    # function; in module form it is not exported.
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"

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

Describe 'New-TransientNetworkRetryStrategy' {

    It 'returns a hashtable with Name and ShouldRetry keys' {
        $strategy = New-TransientNetworkRetryStrategy

        $strategy           | Should -BeOfType [hashtable]
        $strategy.Keys      | Should -Contain 'Name'
        $strategy.Keys      | Should -Contain 'ShouldRetry'
        $strategy.ShouldRetry | Should -BeOfType [scriptblock]
    }

    It 'sets Name to TransientNetwork' {
        (New-TransientNetworkRetryStrategy).Name | Should -Be 'TransientNetwork'
    }
}

Describe 'New-TransientNetworkRetryStrategy ShouldRetry predicate' {

    BeforeAll {
        $script:predicate = (New-TransientNetworkRetryStrategy).ShouldRetry
    }

    It 'returns true for HttpRequestException (DNS / connect failure)' {
        $inner = [System.Net.Sockets.SocketException]::new()
        $ex    = [System.Net.Http.HttpRequestException]::new('dns', $inner)
        $rec   = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for a nested SocketException only reachable via InnerException' {
        # The wrapper (Exception) is a vanilla System.Exception - not on the
        # transient list. The walker must descend into InnerException to find
        # the SocketException underneath.
        $inner = [System.Net.Sockets.SocketException]::new()
        $outer = [Exception]::new('wrapped', $inner)
        $rec   = New-TestErrorRecord -Exception $outer

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for a 5xx HttpResponseException (server error)' {
        $ex  = New-FakeHttpResponseException -StatusCode 503
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns false for a 4xx HttpResponseException (client error)' {
        # Client errors are permanent - retrying a 404 will keep producing 404.
        $ex  = New-FakeHttpResponseException -StatusCode 404
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }

    It 'returns false for a non-network exception (string throw / RuntimeException)' {
        # Mocks elsewhere throw plain strings; the retry layer must not
        # incur delays on those.
        $ex  = [System.Management.Automation.RuntimeException]::new('boom')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }
}
