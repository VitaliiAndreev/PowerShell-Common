BeforeAll {
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-ConstantBackoffStrategy.ps1"
}

Describe 'New-ConstantBackoffStrategy' {

    It 'returns a hashtable with Name and GetDelay keys' {
        $strategy = New-ConstantBackoffStrategy

        $strategy          | Should -BeOfType [hashtable]
        $strategy.Keys     | Should -Contain 'Name'
        $strategy.Keys     | Should -Contain 'GetDelay'
        $strategy.GetDelay | Should -BeOfType [scriptblock]
    }

    It 'sets Name to Constant' {
        (New-ConstantBackoffStrategy).Name | Should -Be 'Constant'
    }
}

Describe 'New-ConstantBackoffStrategy GetDelay' {

    It 'returns the same delay on every attempt' {
        $getDelay = (New-ConstantBackoffStrategy -DelaySeconds 7).GetDelay

        $observed = 1..5 | ForEach-Object { & $getDelay $_ $null }

        $observed | Should -Be @(7, 7, 7, 7, 7)
    }

    It 'closes over DelaySeconds so the strategy survives caller scope' {
        function New-StrategyInChildScope {
            New-ConstantBackoffStrategy -DelaySeconds 9
        }

        $strategy = New-StrategyInChildScope
        & $strategy.GetDelay 1 $null | Should -Be 9
        & $strategy.GetDelay 4 $null | Should -Be 9
    }
}
