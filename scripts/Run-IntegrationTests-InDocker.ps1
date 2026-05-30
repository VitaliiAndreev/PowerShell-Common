<#
.SYNOPSIS
    Runs integration tests for the PowerShell.Common module in Docker.

.DESCRIPTION
    Thin wrapper around the shared Run-IntegrationTests.ps1 action script.
    Each test file runs inside its own PowerShell Docker container; the
    host environment is not affected.

.PARAMETER DockerImage
    Docker image to run tests in. Defaults to
    mcr.microsoft.com/powershell:latest.

.EXAMPLE
    .\Run-IntegrationTests-InDocker.ps1
#>

param(
    [string] $DockerImage = 'mcr.microsoft.com/powershell:latest'
)

# Repo root is one level up now that this script lives under scripts\.
$repoRoot = Split-Path -Parent $PSScriptRoot

& ([IO.Path]::Combine($repoRoot, '.github', 'actions', 'run-integration-tests', 'Run-IntegrationTests.ps1')) `
    -TestsRoot   $repoRoot `
    -DockerImage $DockerImage
