BeforeAll {
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-LinearBackoffStrategy.ps1"
}

Describe 'New-LinearBackoffStrategy' {

    It 'returns a hashtable with Name and GetDelay keys' {
        $strategy = New-LinearBackoffStrategy

        $strategy          | Should -BeOfType [hashtable]
        $strategy.Keys     | Should -Contain 'Name'
        $strategy.Keys     | Should -Contain 'GetDelay'
        $strategy.GetDelay | Should -BeOfType [scriptblock]
    }

    It 'sets Name to Linear' {
        (New-LinearBackoffStrategy).Name | Should -Be 'Linear'
    }
}

Describe 'New-LinearBackoffStrategy GetDelay' {

    It 'grows the delay linearly per attempt up to the cap' {
        $getDelay = (New-LinearBackoffStrategy `
            -StepSeconds 2 `
            -MaxIntervalSeconds 10).GetDelay

        $observed = 1..6 | ForEach-Object { & $getDelay $_ $null }

        # 2,4,6,8,10,10 - the cap clamps anything past attempt 5.
        $observed | Should -Be @(2, 4, 6, 8, 10, 10)
    }

    It 'closes over its parameters so the strategy survives caller scope' {
        function New-StrategyInChildScope {
            New-LinearBackoffStrategy -StepSeconds 5 -MaxIntervalSeconds 100
        }

        $strategy = New-StrategyInChildScope
        & $strategy.GetDelay 1 $null | Should -Be 5
        & $strategy.GetDelay 4 $null | Should -Be 20
    }
}
