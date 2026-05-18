BeforeAll {
    # Dot-source the Public file directly so both the exported factory and
    # the file-private Test-FileLockException land in test scope.
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-FileLockRetryStrategy.ps1"

    # Hand-rolled ErrorRecord factory; same rationale as the
    # transient-network strategy tests.
    function New-TestErrorRecord {
        param([Exception] $Exception)
        return [System.Management.Automation.ErrorRecord]::new(
            $Exception, 'TestError', 'NotSpecified', $null)
    }
}

Describe 'New-FileLockRetryStrategy' {

    It 'returns a hashtable with Name and ShouldRetry keys' {
        $strategy = New-FileLockRetryStrategy

        $strategy             | Should -BeOfType [hashtable]
        $strategy.Keys        | Should -Contain 'Name'
        $strategy.Keys        | Should -Contain 'ShouldRetry'
        $strategy.ShouldRetry | Should -BeOfType [scriptblock]
    }

    It 'sets Name to FileLock' {
        (New-FileLockRetryStrategy).Name | Should -Be 'FileLock'
    }
}

Describe 'New-FileLockRetryStrategy ShouldRetry predicate' {

    BeforeAll {
        $script:predicate = (New-FileLockRetryStrategy).ShouldRetry
    }

    It 'returns true for a direct IOException (the VMMS handle-release case)' {
        $ex  = [System.IO.IOException]::new('file in use')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns true for an IOException reachable only via InnerException' {
        # PowerShell often wraps the underlying IOException in a higher-level
        # exception; the walker must descend through InnerException to find it.
        $inner = [System.IO.IOException]::new('locked')
        $outer = [Exception]::new('wrapped', $inner)
        $rec   = New-TestErrorRecord -Exception $outer

        & $script:predicate $rec | Should -BeTrue
    }

    It 'returns false for UnauthorizedAccessException (permissions, not transient)' {
        # ACL problems will not resolve on their own; retrying just stalls
        # the caller before the real failure surfaces.
        $ex  = [System.UnauthorizedAccessException]::new('denied')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }

    It 'returns false for an unrelated exception (string throw / RuntimeException)' {
        $ex  = [System.Management.Automation.RuntimeException]::new('boom')
        $rec = New-TestErrorRecord -Exception $ex

        & $script:predicate $rec | Should -BeFalse
    }
}
