<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Returns a backoff-strategy
    hashtable consumed by Invoke-WithRetry.
#>

function New-ExponentialBackoffStrategy {
    <#
    .SYNOPSIS
        Builds a backoff strategy hashtable that doubles the delay between
        retries, capped at a configurable ceiling.

    .DESCRIPTION
        Returned shape is the standard backoff-strategy contract consumed
        by Invoke-WithRetry:

            @{
                Name     = 'Exponential'
                GetDelay = { param($Attempt, $LastError) <seconds> }
            }

        Delay formula:

            delay = min(InitialDelaySeconds * 2^(Attempt - 1), MaxIntervalSeconds)

        With the defaults (2s initial, 30s cap) the sequence is
        2, 4, 8, 16, 30, 30, ...

        .GetNewClosure() captures the parameter values into the script
        block so the strategy can be passed around without
        $InitialDelaySeconds / $MaxIntervalSeconds going out of scope.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock     { Invoke-RestMethod $uri } `
            -RetryStrategy   (New-TransientNetworkRetryStrategy) `
            -BackoffStrategy (New-ExponentialBackoffStrategy)
    #>
    [CmdletBinding()]
    param(
        [int] $InitialDelaySeconds = 2,
        [int] $MaxIntervalSeconds  = 30
    )

    return @{
        Name     = 'Exponential'
        GetDelay = {
            param(
                [int] $Attempt,
                [System.Management.Automation.ErrorRecord] $LastError
            )
            [int] [Math]::Min(
                $InitialDelaySeconds * [Math]::Pow(2, $Attempt - 1),
                $MaxIntervalSeconds
            )
        }.GetNewClosure()
    }
}
