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

    Hyper-V VM helpers (SSH execution, host file server) were moved to the
    Infrastructure.HyperV module to keep this module focused on genuinely
    generic utilities. GitHub API helpers live in Infrastructure.GitHub.

    Each function lives in its own file under Public\ and is dot-sourced
    below so diffs stay focused on a single function per commit.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Public\Assert-RequiredProperties.ps1"
. "$PSScriptRoot\Public\ConvertTo-Array.ps1"
. "$PSScriptRoot\Public\Invoke-ModuleInstall.ps1"

# Export-ModuleMember controls what is actually callable after Import-Module.
# It takes precedence over FunctionsToExport in the psd1 at runtime, so both
# must be kept in sync. FunctionsToExport serves a separate purpose: it is
# read by Get-Module -ListAvailable, Find-Module, and PSGallery for fast
# discovery without loading the module. The shared Module.Tests.ps1 in the
# run-unit-tests action enforces that every Public\*.ps1 file appears in both.
Export-ModuleMember -Function `
    Assert-RequiredProperties, `
    ConvertTo-Array, `
    Invoke-ModuleInstall
