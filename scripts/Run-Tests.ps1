<#
.SYNOPSIS
    Runs unit tests for the PowerShell.Common module.

.EXAMPLE
    .\Run-Tests.ps1
#>

# Repo root is one level up now that this script lives under scripts\.
$repoRoot = Split-Path -Parent $PSScriptRoot

& ([IO.Path]::Combine($repoRoot, '.github', 'actions', 'run-unit-tests', 'Run-Tests.ps1')) `
    -TestsRoot $repoRoot
