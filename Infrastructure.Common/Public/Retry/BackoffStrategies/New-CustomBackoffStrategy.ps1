<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Escape hatch for backoff
    policies the built-in factories do not cover (HTTP 429 Retry-After,
    jittered exponential, deadline-aware backoff, ...).
#>

function New-CustomBackoffStrategy {
    <#
    .SYNOPSIS
        Wraps a caller-supplied delay-provider script block in the
        standard backoff-strategy hashtable shape.

    .DESCRIPTION
        Returned shape is the standard backoff-strategy contract consumed
        by Invoke-WithRetry:

            @{
                Name     = <Name>
                GetDelay = <DelayProvider>
            }

        The provided script block is called as
        & $DelayProvider $Attempt $LastError, so it must accept those
        two positional parameters and return a number of seconds.

        Use this when no built-in factory fits - typical cases are
        honouring an HTTP 429 Retry-After header, adding jitter to break
        thundering-herd patterns, or shrinking the delay as a deadline
        approaches.

    .EXAMPLE
        $jittered = New-CustomBackoffStrategy -Name 'JitteredExponential' `
            -DelayProvider {
                param($Attempt, $LastError)
                $base = [Math]::Min(2 * [Math]::Pow(2, $Attempt - 1), 30)
                $base + (Get-Random -Minimum 0 -Maximum 2)
            }

        Invoke-WithRetry -ScriptBlock { ... } -RetryStrategy $s -BackoffStrategy $jittered
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $DelayProvider,
        [string] $Name = 'Custom'
    )

    return @{
        Name     = $Name
        GetDelay = $DelayProvider
    }
}
