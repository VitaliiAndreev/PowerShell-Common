<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Module-internal helper for
    Invoke-WithRetry - kept under Private\ (not Public\) so it is
    excluded from the shared Module.Tests.ps1 export checks: the
    retry/backoff hashtable contract should be free to evolve without
    surfacing through the public API. The strategy factories in this
    module produce well-formed hashtables, so this guard only fires for
    hand-rolled strategies (a supported but error-prone path).
#>

function Assert-RetryStrategyShape {
    <#
    .SYNOPSIS
        Validates that a strategy hashtable carries the keys Invoke-WithRetry
        expects, throwing a descriptive ArgumentException if not.

    .DESCRIPTION
        Front-loaded so a malformed strategy fails fast at the entry of
        Invoke-WithRetry rather than mid-retry, where the failure mode
        would be confusing (a NullReferenceException from inside the loop
        body, for instance).

        Parameterised over -Kind / -ActionKey so the same helper covers
        both retry (ShouldRetry) and backoff (GetDelay) strategies; the
        error messages name the offending kind so the caller can fix the
        right hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Strategy,
        [Parameter(Mandatory)] [string]    $Kind,        # 'Retry' or 'Backoff'
        [Parameter(Mandatory)] [string]    $ActionKey    # 'ShouldRetry' or 'GetDelay'
    )

    if (-not $Strategy.ContainsKey('Name') -or $Strategy.Name -isnot [string]) {
        throw [System.ArgumentException]::new(
            "$Kind strategy is missing a string 'Name' key.")
    }
    if (-not $Strategy.ContainsKey($ActionKey) -or
        $Strategy[$ActionKey] -isnot [scriptblock]) {
        throw [System.ArgumentException]::new(
            "$Kind strategy '$($Strategy.Name)' is missing a scriptblock " +
            "'$ActionKey' key.")
    }
}
