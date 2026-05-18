<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. Generic retry loop that
    consumes hashtable-shaped retry and backoff strategies (see the
    factories under Public/Retry/TransientErrorStrategies/ and
    Public/Retry/BackoffStrategies/). Strategy-shape validation lives in
    the sibling Assert-RetryStrategyShape.ps1 (file-private helper).
#>

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Runs a script block and retries on failures matched by one or more
        retry strategies, sleeping between attempts according to a backoff
        strategy.

    .DESCRIPTION
        Generic retry primitive. The classification of "what counts as
        retryable" is supplied by hashtable-shaped retry strategies
        (see New-TransientNetworkRetryStrategy, New-FileLockRetryStrategy)
        and the inter-attempt pacing by a backoff strategy
        (see New-ExponentialBackoffStrategy and friends).

        Multiple retry strategies are OR-composed: if any of their
        ShouldRetry predicates returns $true the loop retries; if none
        match the failure propagates immediately. This lets a single call
        site cover several legitimately-transient failure classes (e.g.
        network plus file-lock) without authoring a bespoke classifier.

        -BackoffStrategy defaults to New-ExponentialBackoffStrategy
        (2s -> 4s -> 8s, capped at 30s) because that policy fits both
        currently known call sites (HTTP + file-lock). Callers wanting
        a different curve pass one explicitly.

    .PARAMETER ScriptBlock
        The work to attempt. Its return value is the function's return
        value on success.

    .PARAMETER RetryStrategy
        One or more strategy hashtables of shape
        @{ Name = <string>; ShouldRetry = <scriptblock> }. Mandatory so a
        missing argument cannot silently mean "never retry".

    .PARAMETER BackoffStrategy
        A single backoff hashtable of shape
        @{ Name = <string>; GetDelay = <scriptblock> }. Defaults to
        New-ExponentialBackoffStrategy.

    .PARAMETER MaxAttempts
        Total attempts including the first. Defaults to 3. Pass 1 to
        disable retry entirely (handy in tests with deterministic
        failures).

    .PARAMETER OperationName
        Label surfaced in the per-retry warning. Defaults to 'operation'.

    .EXAMPLE
        Invoke-WithRetry `
            -OperationName 'Adoptium release lookup' `
            -RetryStrategy (New-TransientNetworkRetryStrategy) `
            -ScriptBlock   { Invoke-RestMethod $uri }

    .EXAMPLE
        Invoke-WithRetry `
            -OperationName 'delete VHDX' `
            -RetryStrategy (New-FileLockRetryStrategy) `
            -MaxAttempts   5 `
            -ScriptBlock   { Remove-Item $vhdxPath -Force -ErrorAction Stop }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory)]
        [hashtable[]] $RetryStrategy,

        [hashtable] $BackoffStrategy,

        [int] $MaxAttempts = 3,

        [string] $OperationName = 'operation'
    )

    # Default the backoff lazily so callers do not pay for the factory call
    # when they pass an explicit strategy (also keeps the parameter default
    # free of an executable expression, which PowerShell evaluates at
    # parameter-binding time in an unpredictable scope).
    if (-not $BackoffStrategy) {
        $BackoffStrategy = New-ExponentialBackoffStrategy
    }

    # Validate all strategies up front so a malformed hashtable fails fast
    # rather than mid-retry. Each retry-strategy item is checked
    # individually so the error names the offending one.
    foreach ($rs in $RetryStrategy) {
        Assert-RetryStrategyShape -Strategy $rs `
            -Kind 'Retry' -ActionKey 'ShouldRetry'
    }
    Assert-RetryStrategyShape -Strategy $BackoffStrategy `
        -Kind 'Backoff' -ActionKey 'GetDelay'

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $err = $_

            # OR-composition: the first matching strategy wins. Its Name is
            # surfaced in the warning so the operator can tell which policy
            # fired when several are composed.
            $matched = $RetryStrategy |
                Where-Object { & $_.ShouldRetry $err } |
                Select-Object -First 1

            # No policy matched - failure is permanent, propagate the
            # original error so the caller sees the underlying cause.
            if (-not $matched) { throw }

            # Last attempt - propagate rather than wrapping in a generic
            # "gave up" error; the underlying failure is what operators
            # need to act on.
            if ($attempt -ge $MaxAttempts) { throw }

            $delay = & $BackoffStrategy.GetDelay $attempt $err

            Write-Warning (
                "$OperationName failed (attempt $attempt/$MaxAttempts, " +
                "strategy=$($matched.Name)): " +
                "$($err.Exception.Message). Retrying in ${delay}s ..."
            )
            Start-Sleep -Seconds $delay
        }
    }
}
