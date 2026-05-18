<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Returns a backoff-strategy
    hashtable consumed by Invoke-WithRetry.
#>

function New-ConstantBackoffStrategy {
    <#
    .SYNOPSIS
        Builds a backoff strategy hashtable that returns the same delay on
        every attempt.

    .DESCRIPTION
        Returned shape is the standard backoff-strategy contract consumed
        by Invoke-WithRetry:

            @{
                Name     = 'Constant'
                GetDelay = { param($Attempt, $LastError) <seconds> }
            }

        Useful when the underlying failure has a known fixed recovery
        window (e.g. a service restart cycle) and exponential growth
        would just oversleep without improving the success rate.

        .GetNewClosure() captures $DelaySeconds into the script block so
        the strategy can be passed around without the parameter going out
        of scope.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock     { ... } `
            -RetryStrategy   $strategy `
            -BackoffStrategy (New-ConstantBackoffStrategy -DelaySeconds 5)
    #>
    [CmdletBinding()]
    param(
        [int] $DelaySeconds = 2
    )

    return @{
        Name     = 'Constant'
        GetDelay = {
            param(
                [int] $Attempt,
                [System.Management.Automation.ErrorRecord] $LastError
            )
            $DelaySeconds
        }.GetNewClosure()
    }
}
