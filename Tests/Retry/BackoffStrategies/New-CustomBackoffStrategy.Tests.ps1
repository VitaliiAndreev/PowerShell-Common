BeforeAll {
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-CustomBackoffStrategy.ps1"
}

Describe 'New-CustomBackoffStrategy' {

    It 'returns a hashtable with Name and GetDelay keys' {
        $strategy = New-CustomBackoffStrategy -DelayProvider { param($a, $e) 1 }

        $strategy          | Should -BeOfType [hashtable]
        $strategy.Keys     | Should -Contain 'Name'
        $strategy.Keys     | Should -Contain 'GetDelay'
        $strategy.GetDelay | Should -BeOfType [scriptblock]
    }

    It 'defaults Name to Custom when not supplied' {
        $strategy = New-CustomBackoffStrategy -DelayProvider { param($a, $e) 1 }
        $strategy.Name | Should -Be 'Custom'
    }

    It 'passes the caller-supplied Name through' {
        $strategy = New-CustomBackoffStrategy `
            -Name 'JitteredExponential' `
            -DelayProvider { param($a, $e) 1 }

        $strategy.Name | Should -Be 'JitteredExponential'
    }

    It 'requires -DelayProvider' {
        # The factory has no useful default to fall back on; omitting the
        # provider must fail loudly rather than silently returning a noop.
        { New-CustomBackoffStrategy } | Should -Throw
    }

    It 'invokes the supplied script block as GetDelay' {
        # Verify the exact instance flows through (not a wrapper that
        # re-emits the same values) by checking the closed-over counter
        # the caller's provider mutates.
        $script:calls = 0
        $provider = {
            param($Attempt, $LastError)
            $script:calls++
            $Attempt * 10
        }

        $strategy = New-CustomBackoffStrategy -DelayProvider $provider

        & $strategy.GetDelay 1 $null | Should -Be 10
        & $strategy.GetDelay 3 $null | Should -Be 30
        $script:calls | Should -Be 2
    }
}
