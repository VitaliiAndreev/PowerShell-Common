<#
.SYNOPSIS
    Runs SSH integration tests against a Docker target container.

.DESCRIPTION
    Builds the SSH test image from the Dockerfile in the GitHub-Common
    repo (resolved as a sibling checkout next to this repo, skipped when
    the image already exists locally), then runs every *.Tests.ps1 file
    found under Tests/Integration/ directly on the host.

    This mirrors what ci-powershell-docker-target.yml does in CI, minus
    the GitHub Actions layer cache. Tests connect to the Docker container
    via SSH on localhost:2222 - the container lifecycle is managed by the
    test suite itself (e.g. Initialize-SshEnvironment.ps1 / BeforeAll).

    Requires Docker to be available and running.

.PARAMETER TestsRoot
    Root of the repo under test. Tests\Integration\ must be a direct child.
    Defaults to the PowerShell-Common root (for testing Common itself).
    Consumer repos pass their own root:
        .ci-common\Run-IntegrationTests-AgainstDockerTarget.ps1 `
            -TestsRoot $PSScriptRoot

.EXAMPLE
    .\Run-IntegrationTests-AgainstDockerTarget.ps1

.EXAMPLE
    .ci-common\Run-IntegrationTests-AgainstDockerTarget.ps1 `
        -TestsRoot <path-to-Infrastructure-GitHubRunners>
#>

param(
    [string] $TestsRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:ImageName   = 'infra-ssh-test-image'

# GitHub-Common is checked out as a sibling of PowerShell-Common under
# the shared repos root. Resolve the Dockerfile from there rather than
# relying on an env var the local dev never sets.
$Script:ReposRoot     = Split-Path -Parent $PSScriptRoot
$Script:DockerfileDir = [IO.Path]::Combine(
    $Script:ReposRoot, 'GitHub-Common',
    '.github', 'actions', 'build-ssh-test-image')

# ---------------------------------------------------------------------------
# Verify Docker is available.
# ---------------------------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker is not available. Install Docker Desktop and ensure it is running.'
}

# ---------------------------------------------------------------------------
# Build the SSH test image if it is not already present locally.
#   CI pre-builds it via the build-ssh-test-image action with GHA layer
#   caching. Locally the build runs once and the image is reused on
#   subsequent runs.
# ---------------------------------------------------------------------------

$existingImage = docker images -q $Script:ImageName 2>&1
if ($existingImage) {
    Write-Host 'SSH test image already present - skipping build.' -ForegroundColor Cyan
} else {
    if (-not (Test-Path $Script:DockerfileDir)) {
        throw ("GitHub-Common Dockerfile not found at $Script:DockerfileDir. " +
               'Expected GitHub-Common to be checked out as a sibling of this repo.')
    }
    Write-Host 'Building SSH test image...' -ForegroundColor Cyan
    docker build -t $Script:ImageName $Script:DockerfileDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build Docker image '$Script:ImageName'."
    }
}

# ---------------------------------------------------------------------------
# Ensure Pester 5 is available on the host.
# ---------------------------------------------------------------------------

$pester = Get-Module -ListAvailable -Name Pester |
    Where-Object { $_.Version.Major -ge 5 } |
    Sort-Object Version -Descending |
    Select-Object -First 1

if (-not $pester) {
    Write-Host 'Pester 5 not found - installing...' -ForegroundColor Cyan
    Install-Module -Name Pester -MinimumVersion 5.0 `
        -Scope CurrentUser -Force -SkipPublisherCheck
}

Import-Module Pester -MinimumVersion 5.0

# ---------------------------------------------------------------------------
# Run integration tests directly on the host.
#   Tests manage the container lifecycle themselves via BeforeAll/AfterAll.
# ---------------------------------------------------------------------------

$integrationDir = [IO.Path]::Combine($TestsRoot, 'Tests', 'Integration.DockerTarget')

if (-not (Test-Path $integrationDir)) {
    Write-Host "No Tests\Integration\ directory found under $TestsRoot - nothing to run." `
        -ForegroundColor Yellow
    exit 0
}

$config = New-PesterConfiguration
$config.Run.Path         = $integrationDir
$config.Output.Verbosity = 'Detailed'
$config.Run.PassThru     = $true

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    Write-Host "$($result.FailedCount) test(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host 'All SSH integration tests passed.' -ForegroundColor Green
