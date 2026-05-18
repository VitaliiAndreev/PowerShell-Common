BeforeAll {
    # Dot-source the loop plus the default-backoff factory it falls back to
    # when no -BackoffStrategy is supplied. Strategy factories used by the
    # specific assertions are sourced as needed alongside.
    . "$PSScriptRoot\..\..\Infrastructure.Common\Private\Retry\Assert-RetryStrategyShape.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
    . "$PSScriptRoot\..\..\Infrastructure.Common\Public\Retry\Invoke-WithRetry.ps1"

    # Test-only zero-delay backoff so the suite stays fast and deterministic.
    function New-NoSleepBackoff {
        @{
            Name     = 'NoSleep'
            GetDelay = { param($Attempt, $LastError) 0 }
        }
    }

    # Predicates as named factories so each It uses a self-describing strategy.
    function New-AlwaysRetryStrategy {
        @{
            Name        = 'Always'
            ShouldRetry = { param($err) $true }
        }
    }

    function New-NeverRetryStrategy {
        @{
            Name        = 'Never'
            ShouldRetry = { param($err) $false }
        }
    }
}

Describe 'Invoke-WithRetry - happy path' {

    It 'returns the script block result on first-attempt success without sleeping' {
        $script:_calls = 0
        # Backoff intentionally throws so the test fails loudly if the loop
        # ever sleeps on a successful first attempt.
        $explodingBackoff = @{
            Name     = 'Exploding'
            GetDelay = { param($a, $e) throw 'GetDelay must not be called on success' }
        }

        $result = Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy $explodingBackoff `
            -ScriptBlock     {
                $script:_calls++
                return 'ok'
            }

        $result         | Should -Be 'ok'
        $script:_calls  | Should -Be 1
    }
}

Describe 'Invoke-WithRetry - parameter validation' {

    It 'throws when -RetryStrategy is omitted (mandatory)' {
        # Pester captures the parameter-binding error; -ErrorAction Stop is
        # set in module scope so the missing-mandatory path becomes a throw.
        { Invoke-WithRetry -ScriptBlock { 'noop' } } |
            Should -Throw
    }

    It 'throws a descriptive error when a retry strategy is missing ShouldRetry' {
        $bad = @{ Name = 'Broken' }

        { Invoke-WithRetry `
            -RetryStrategy $bad `
            -ScriptBlock   { 'noop' }
        } | Should -Throw "*'ShouldRetry'*"
    }

    It 'throws a descriptive error when a retry strategy is missing Name' {
        $bad = @{ ShouldRetry = { param($e) $true } }

        { Invoke-WithRetry `
            -RetryStrategy $bad `
            -ScriptBlock   { 'noop' }
        } | Should -Throw "*'Name'*"
    }

    It 'throws a descriptive error when the backoff strategy is missing GetDelay' {
        $badBackoff = @{ Name = 'Broken' }

        { Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy $badBackoff `
            -ScriptBlock     { 'noop' }
        } | Should -Throw "*'GetDelay'*"
    }
}

Describe 'Invoke-WithRetry - retry decision' {

    It 'retries while the single predicate returns $true and stops on success' {
        $script:_attempts = 0
        $result = Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy (New-NoSleepBackoff) `
            -ScriptBlock     {
                $script:_attempts++
                if ($script:_attempts -lt 3) { throw 'transient' }
                return 'done'
            }

        $result            | Should -Be 'done'
        $script:_attempts  | Should -Be 3
    }

    It 'propagates immediately when no strategy matches (no sleep, single call)' {
        $script:_count = 0
        # GetDelay throws so the test fails if the loop ever sleeps on a
        # permanent failure - the strongest guarantee that no retry was
        # attempted.
        $explodingBackoff = @{
            Name     = 'Exploding'
            GetDelay = { param($a, $e) throw 'must not sleep on permanent' }
        }

        { Invoke-WithRetry `
            -RetryStrategy   (New-NeverRetryStrategy) `
            -BackoffStrategy $explodingBackoff `
            -ScriptBlock     {
                $script:_count++
                throw 'permanent'
            }
        } | Should -Throw '*permanent*'

        $script:_count | Should -Be 1
    }

    It 'retries when any of several strategies matches' {
        # First strategy never matches; the second one accepts the error.
        # Verifies OR-composition rather than first-strategy-wins-only.
        $matchOnExceptionMessage = @{
            Name        = 'OnMessage'
            ShouldRetry = { param($err) $err.Exception.Message -eq 'pick-me' }
        }
        $script:_attempts = 0
        $result = Invoke-WithRetry `
            -RetryStrategy   @((New-NeverRetryStrategy), $matchOnExceptionMessage) `
            -BackoffStrategy (New-NoSleepBackoff) `
            -ScriptBlock     {
                $script:_attempts++
                if ($script:_attempts -lt 2) { throw 'pick-me' }
                return 'ok'
            }

        $result            | Should -Be 'ok'
        $script:_attempts  | Should -Be 2
    }

    It 'gives up after MaxAttempts and rethrows the underlying error' {
        $script:_tries = 0
        { Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy (New-NoSleepBackoff) `
            -MaxAttempts     3 `
            -ScriptBlock     {
                $script:_tries++
                throw 'still-failing'
            }
        } | Should -Throw '*still-failing*'

        $script:_tries | Should -Be 3
    }
}

Describe 'Invoke-WithRetry - backoff integration' {

    It 'invokes the supplied BackoffStrategy.GetDelay with attempt number and last error' {
        # Capture every (Attempt, ErrorMessage) tuple GetDelay was called with.
        # Asserts both the call count and the actual arguments, so a future
        # refactor that drops one of the parameters fails loudly.
        $script:_calls = New-Object System.Collections.Generic.List[object]
        $fakeBackoff = @{
            Name     = 'Fake'
            GetDelay = {
                param($Attempt, $LastError)
                $script:_calls.Add([pscustomobject]@{
                    Attempt = $Attempt
                    Message = $LastError.Exception.Message
                })
                return 0
            }
        }

        $script:_attempts = 0
        Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy $fakeBackoff `
            -MaxAttempts     3 `
            -ScriptBlock     {
                $script:_attempts++
                if ($script:_attempts -lt 3) {
                    throw "fail-$script:_attempts"
                }
                return 'ok'
            } | Out-Null

        # Two failures before the third-attempt success -> two GetDelay calls.
        $script:_calls.Count    | Should -Be 2
        $script:_calls[0].Attempt | Should -Be 1
        $script:_calls[0].Message | Should -Be 'fail-1'
        $script:_calls[1].Attempt | Should -Be 2
        $script:_calls[1].Message | Should -Be 'fail-2'
    }

    It 'is not called by GetDelay on the final attempt (rethrow happens first)' {
        # If the loop calls GetDelay after the last failure it would sleep
        # before throwing, wasting time on a guaranteed-failed call.
        $script:_delayCalls = 0
        $countingBackoff = @{
            Name     = 'Counting'
            GetDelay = {
                param($a, $e)
                $script:_delayCalls++
                return 0
            }
        }

        { Invoke-WithRetry `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy $countingBackoff `
            -MaxAttempts     3 `
            -ScriptBlock     { throw 'boom' }
        } | Should -Throw '*boom*'

        # 3 attempts -> 2 inter-attempt sleeps -> 2 GetDelay calls.
        $script:_delayCalls | Should -Be 2
    }

    It 'defaults to New-ExponentialBackoffStrategy when -BackoffStrategy is omitted' {
        # Stub Start-Sleep so the suite stays fast; capture the delays the
        # loop chooses so we can verify the default curve.
        $script:_observedDelays = @()

        # Shadow Start-Sleep in this scope only. Pester's Mock would also
        # work, but a local function keeps this file Pester-version agnostic.
        function Start-Sleep {
            param([int] $Seconds)
            $script:_observedDelays += $Seconds
        }

        $script:_attempts = 0
        try {
            Invoke-WithRetry `
                -RetryStrategy (New-AlwaysRetryStrategy) `
                -MaxAttempts   3 `
                -ScriptBlock   {
                    $script:_attempts++
                    throw 'transient'
                }
        } catch { } # exhaustion is expected; we only care about the delays

        # Exponential defaults: 2 * 2^(attempt - 1) capped at 30 -> 2, 4.
        $script:_observedDelays | Should -Be @(2, 4)
    }
}

Describe 'Invoke-WithRetry - warning output' {

    It 'surfaces OperationName and the matched strategy name in the retry warning' {
        # Capture warnings via -WarningVariable rather than redirecting
        # streams: keeps assertions on structured data rather than parsed
        # console text.
        Invoke-WithRetry `
            -OperationName   'fetch widget' `
            -RetryStrategy   (New-AlwaysRetryStrategy) `
            -BackoffStrategy (New-NoSleepBackoff) `
            -MaxAttempts     2 `
            -WarningAction   SilentlyContinue `
            -WarningVariable warnings `
            -ScriptBlock     {
                if (-not $script:_succeeded) {
                    $script:_succeeded = $true
                    throw 'first call fails'
                }
                return 'ok'
            } | Out-Null

        $warnings.Count        | Should -Be 1
        [string]$warnings[0]   | Should -Match 'fetch widget'
        [string]$warnings[0]   | Should -Match 'strategy=Always'
    }
}
