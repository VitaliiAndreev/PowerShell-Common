<#
.NOTES
    Dot-sourced by Infrastructure.Common.psm1. The public surface is
    New-FileLockRetryStrategy; Test-FileLockException is a file-private
    helper kept alongside the factory so the classification policy lives
    next to its sole consumer.
#>

# ---------------------------------------------------------------------------
# Test-FileLockException (private)
#   Returns $true when the failure looks like another process holds a
#   handle on the target file. The canonical case is Hyper-V's VMMS
#   service releasing VHDX handles asynchronously after Remove-VM:
#   Remove-Item then throws System.IO.IOException
#   ("The process cannot access the file ... because it is being used by
#    another process") for a few seconds.
#
#   The helper walks the InnerException chain because higher-level
#   PowerShell errors often wrap the IOException several layers deep.
#
#   UnauthorizedAccessException is intentionally NOT matched: it signals
#   a permissions problem that will not resolve on its own, so retrying
#   would just stall the caller before the real error surfaces.
# ---------------------------------------------------------------------------

function Test-FileLockException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $ex = $ErrorRecord.Exception
    while ($null -ne $ex) {
        if ($ex -is [System.IO.IOException]) {
            return $true
        }
        $ex = $ex.InnerException
    }

    return $false
}

function New-FileLockRetryStrategy {
    <#
    .SYNOPSIS
        Builds a retry strategy hashtable that matches file-lock failures
        (System.IO.IOException anywhere in the exception chain).

    .DESCRIPTION
        Returned shape is the standard retry-strategy contract consumed by
        Invoke-WithRetry:

            @{
                Name        = 'FileLock'
                ShouldRetry = { param($err) <bool> }
            }

        Designed for the Hyper-V VMMS handle-release case where
        Remove-Item briefly fails with IOException after Remove-VM
        completes. UnauthorizedAccessException is not matched - it is
        a permissions problem, not a transient lock.

    .EXAMPLE
        Invoke-WithRetry `
            -ScriptBlock   { Remove-Item -Path $vhdxPath -Force -ErrorAction Stop } `
            -RetryStrategy (New-FileLockRetryStrategy) `
            -MaxAttempts   5
    #>
    [CmdletBinding()]
    param()

    return @{
        Name        = 'FileLock'
        ShouldRetry = {
            param([System.Management.Automation.ErrorRecord] $ErrorRecord)
            Test-FileLockException -ErrorRecord $ErrorRecord
        }
    }
}
