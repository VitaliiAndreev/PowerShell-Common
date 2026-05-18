BeforeAll {
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
}

Describe 'New-ExponentialBackoffStrategy' {

    It 'returns a hashtable with Name and GetDelay keys' {
        $strategy = New-ExponentialBackoffStrategy

        $strategy          | Should -BeOfType [hashtable]
        $strategy.Keys     | Should -Contain 'Name'
        $strategy.Keys     | Should -Contain 'GetDelay'
        $strategy.GetDelay | Should -BeOfType [scriptblock]
    }

    It 'sets Name to Exponential' {
        (New-ExponentialBackoffStrategy).Name | Should -Be 'Exponential'
    }
}

Describe 'New-ExponentialBackoffStrategy GetDelay' {

    It 'doubles the delay each attempt up to the cap (defaults: 2s -> 30s)' {
        # Defaults: InitialDelaySeconds=2, MaxIntervalSeconds=30 -> the
        # canonical 2,4,8,16,30,30 sequence.
        $getDelay = (New-ExponentialBackoffStrategy).GetDelay

        $observed = 1..6 | ForEach-Object { & $getDelay $_ $null }

        $observed | Should -Be @(2, 4, 8, 16, 30, 30)
    }

    It 'honours custom InitialDelaySeconds and MaxIntervalSeconds' {
        $getDelay = (New-ExponentialBackoffStrategy `
            -InitialDelaySeconds 1 `
            -MaxIntervalSeconds  10).GetDelay

        $observed = 1..5 | ForEach-Object { & $getDelay $_ $null }

        $observed | Should -Be @(1, 2, 4, 8, 10)
    }

    It 'closes over its parameters so the strategy survives caller scope' {
        # The factory must capture InitialDelaySeconds / MaxIntervalSeconds
        # at construction time. If GetNewClosure is dropped, the script
        # block would look up the parameters in the wrong scope and either
        # error under StrictMode or return wrong values.
        function New-StrategyInChildScope {
            New-ExponentialBackoffStrategy -InitialDelaySeconds 3 -MaxIntervalSeconds 100
        }

        $strategy = New-StrategyInChildScope
        & $strategy.GetDelay 1 $null | Should -Be 3
        & $strategy.GetDelay 3 $null | Should -Be 12
    }
}
