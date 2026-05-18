<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Returns a backoff-strategy
    hashtable consumed by Invoke-WithRetry.
#>

function New-LinearBackoffStrategy {
    <#
    .SYNOPSIS
        Builds a backoff strategy hashtable that grows the delay linearly
        with the attempt number, capped at a configurable ceiling.

    .DESCRIPTION
        Returned shape is the standard backoff-strategy contract consumed
        by Invoke-WithRetry:

            @{
                Name     = 'Linear'
                GetDelay = { param($Attempt, $LastError) <seconds> }
            }

        Delay formula:

            delay = min(StepSeconds * Attempt, MaxIntervalSeconds)

        Useful when exponential growth ramps up too fast (e.g. operator
        retries the caller manually and wants predictable spacing) but a
        flat constant is too slow to back off.

        .GetNewClosure() captures the parameter values into the script
        block so the strategy can be passed around without $StepSeconds /
        $MaxIntervalSeconds going out of scope.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock     { ... } `
            -RetryStrategy   $strategy `
            -BackoffStrategy (New-LinearBackoffStrategy -StepSeconds 2 -MaxIntervalSeconds 10)
    #>
    [CmdletBinding()]
    param(
        [int] $StepSeconds        = 2,
        [int] $MaxIntervalSeconds = 30
    )

    return @{
        Name     = 'Linear'
        GetDelay = {
            param(
                [int] $Attempt,
                [System.Management.Automation.ErrorRecord] $LastError
            )
            [int] [Math]::Min($StepSeconds * $Attempt, $MaxIntervalSeconds)
        }.GetNewClosure()
    }
}
