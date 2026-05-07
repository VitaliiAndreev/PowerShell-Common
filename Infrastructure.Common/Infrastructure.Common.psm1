<#
.SYNOPSIS
    Shared PowerShell utilities for infrastructure repos.

.DESCRIPTION
    Provides cross-cutting utilities that are not specific to any single
    infrastructure concern (secrets, provisioning, users, etc.).

    Current functions:
    - Assert-RequiredProperties: validates object fields are present and
      non-empty; throws a descriptive error if not.
    - ConvertTo-Array: ensures a value is always an array regardless of
      whether PowerShell unrolled a single-item collection.
    - Invoke-ModuleInstall: installs a PSGallery module if absent or below a
      minimum version, then imports it.
    - Invoke-SshClientCommand: runs a shell command on a remote host via an SSH.NET
      SshClient and returns a normalised result object (Output, Error,
      ExitStatus).
    - Invoke-WithVmFileServer: runs a script block with a live file server
      handle, guaranteeing cleanup in a finally block. Start-VmFileServer,
      Stop-VmFileServer, and Get-VmSwitchHostIp are private helpers called
      internally by this function.
    - Add-VmFileServerFile: copies a host-side file into the server's staging
      directory and returns its download URL. Idempotent by name and size.

    Each function lives in its own file under Public\ or Private\ and is
    dot-sourced below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Private\Get-VmSwitchHostIp.ps1"
. "$PSScriptRoot\Private\Start-VmFileServer.ps1"
. "$PSScriptRoot\Private\Stop-VmFileServer.ps1"
. "$PSScriptRoot\Public\Add-VmFileServerFile.ps1"
. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\ConvertTo-Array.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"
. "$PSScriptRoot\Public\Invoke-SshClientCommand.ps1"
. "$PSScriptRoot\Public\Invoke-WithVmFileServer.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function `
    Add-VmFileServerFile, `
    Assert-RequiredProperties, `
    ConvertTo-Array, `
    Invoke-ModuleInstall, `
    Invoke-SshClientCommand, `
    Invoke-WithVmFileServer
