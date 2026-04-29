# Infrastructure-Common

Shared PowerShell module providing common utilities for the
`Infrastructure-*` polyrepo family.

## Index

- [Requirements](#requirements)
- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
- [API reference](#api-reference)
  - [Assert-RequiredProperties](#assert-requiredproperties)
  - [Get-GitHubAppToken](#get-githubapptoken)
  - [Get-PendingDeployment](#get-pendingdeployment)
  - [Invoke-GitHubApi](#invoke-githubapi)
  - [Invoke-ModuleInstall](#invoke-moduleinstall)
  - [Invoke-SshClientCommand](#invoke-sshclientcommand)
  - [Set-DeploymentStatus](#set-deploymentstatus)
- [Repo structure](#repo-structure)

---

## Requirements

PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is not supported.

---

## Overview

Provides utilities used by all infrastructure repos so the logic does not
need to be duplicated and tested in each one independently:

- **`Assert-RequiredProperties`** - validates that a PSCustomObject has all
  required properties present and non-empty; collects every violation before
  throwing so the consumer sees the full picture in one run.
- **`Get-GitHubAppToken`** - exchanges a GitHub App private key (`.pem`) for
  a short-lived installation access token. Builds and signs a JWT with RS256,
  then calls the GitHub Apps API to obtain a bearer token valid for 1 hour.
  Requires PowerShell 7+.
- **`Get-PendingDeployment`** - queries the GitHub Deployments API for the
  given environment and returns the oldest deployment that has not yet reached
  a terminal status (`success`, `failure`, `error`, `inactive`), or `$null`
  if none exists. Used by the E2E polling agent to detect work to do.
- **`Invoke-GitHubApi`** - general-purpose GitHub REST API caller; handles
  authentication, User-Agent, and JSON body serialization so callers only
  supply a token, URI, and optional body. Accepts both PATs and GitHub App
  installation tokens.
- **`Invoke-ModuleInstall`** - installs a module from PSGallery if absent or
  below the required minimum version, then imports it.
- **`Set-DeploymentStatus`** - posts a status update to an existing GitHub
  deployment. Used by the E2E polling agent to mark a deployment as
  `in_progress` when picked up and `success` or `failure` when tests finish.
- **`Invoke-SshClientCommand`** - runs a shell command on a remote host via an
  SSH.NET `SshClient` and returns a normalised result object (`Output`,
  `Error`, `ExitStatus`). Uses SSH.NET directly rather than Posh-SSH cmdlets
  to avoid a Posh-SSH 3.x bug that breaks key exchange against
  OpenSSH 9.x (Ubuntu 24.04).

### Bootstrap note

`Invoke-ModuleInstall` cannot install itself. Each consumer script that needs
this module must include a short inline guard to install `Infrastructure.Common`
first — this is a one-time cost per script, and all other module installs then
flow through `Invoke-ModuleInstall`.

```powershell
# Inline bootstrap - cannot use Invoke-ModuleInstall to install itself.
$_common = Get-Module -ListAvailable -Name Infrastructure.Common |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $_common -or $_common.Version -lt [Version]'1.2.1') {
    Install-Module Infrastructure.Common -Scope CurrentUser -Force
}
Import-Module Infrastructure.Common -Force -ErrorAction Stop
```

---

## Installation

Consuming repos install automatically from PSGallery via the bootstrap block
above — no manual step needed.

To install manually:

```powershell
Install-Module Infrastructure.Common -Scope CurrentUser
```

To update an existing installation:

```powershell
Update-Module Infrastructure.Common
```

**For local development of this module:** use `Install.ps1` to install from
source instead of PSGallery.

---

## Publishing

Publishing is fully automated via GitHub Actions.

**To ship a new version:**

1. Bump `ModuleVersion` in [Infrastructure.Common/Infrastructure.Common.psd1](Infrastructure.Common/Infrastructure.Common.psd1)
2. Open a PR, get it reviewed and merged

On merge, [.github/workflows/tag.yml](.github/workflows/tag.yml) runs both
the unit and integration test workflows, creates a matching git tag, then
calls [.github/workflows/publish.yml](.github/workflows/publish.yml) to
publish to PSGallery. No manual tagging step required.

**One-time setup:** add your PSGallery API key as a repository secret named
`PSGALLERY_API_KEY` under Settings -> Secrets and variables -> Actions.
Generate a key at [powershellgallery.com/account/apikeys](https://www.powershellgallery.com/account/apikeys).

---

## API reference

### `Assert-RequiredProperties`

Validates that a PSCustomObject has all required properties present and
non-empty. All violations are collected before throwing so the consumer
sees the full picture in one run rather than fixing one field at a time.

| Parameter      | Type          | Required | Description                                              |
|----------------|---------------|----------|----------------------------------------------------------|
| `-Object`      | object        | Yes      | The PSCustomObject to validate (e.g. a config entry)     |
| `-Properties`  | string[]      | Yes      | Property names that must be present and non-empty        |
| `-Context`     | string        | Yes      | Identifies the object in error messages, e.g. `"VM 'ubuntu-01'"` |

```powershell
Assert-RequiredProperties -Object $vm `
    -Properties @('vmName', 'ipAddress') `
    -Context "VM '$($vm.vmName)'"
```

---

### `Get-GitHubAppToken`

Exchanges a GitHub App private key for a short-lived installation access
token. Signs a JWT with RS256 and calls
`POST /app/installations/{id}/access_tokens`. Requires PowerShell 7+.

| Parameter          | Type   | Required | Description                                           |
|--------------------|--------|----------|-------------------------------------------------------|
| `-AppId`           | int    | Yes      | GitHub App ID (shown under "App ID" on the app page)  |
| `-InstallationId`  | int    | Yes      | Installation ID for the target repo or organisation   |
| `-PrivateKeyPath`  | string | Yes      | Path to the RSA private key `.pem` downloaded from GitHub |

Returns a `PSCustomObject` with:

| Property     | Type   | Description                                    |
|--------------|--------|------------------------------------------------|
| `Token`      | string | Bearer token; pass to `Invoke-GitHubApi`       |
| `ExpiresAt`  | string | ISO 8601 expiry timestamp (1 hour from issue)  |

```powershell
$appToken = Get-GitHubAppToken `
    -AppId          $appId `
    -InstallationId $installationId `
    -PrivateKeyPath 'C:\private\my-app.private-key.pem'

# Token is valid for 1 hour; refresh before ExpiresAt - 5 minutes.
$runners = Invoke-GitHubApi -Token $appToken.Token `
    -Uri 'https://api.github.com/repos/owner/repo/actions/runners'
```

---

### `Get-PendingDeployment`

Returns the oldest deployment for the given repo and environment that has not
yet reached a terminal status (`success`, `failure`, `error`, `inactive`).
Returns `$null` when there is nothing to process. Used by the E2E polling agent
on each tick to detect work to do.

| Parameter       | Type   | Required | Description                                           |
|-----------------|--------|----------|-------------------------------------------------------|
| `-Token`        | string | Yes      | Bearer token - PAT or GitHub App installation token   |
| `-Owner`        | string | Yes      | GitHub organisation or user that owns the repo        |
| `-Repo`         | string | Yes      | Repository name (without the owner prefix)            |
| `-Environment`  | string | Yes      | Deployment environment name to filter by              |

Returns a GitHub deployment object (or `$null`).

```powershell
$deployment = Get-PendingDeployment `
    -Token       $token `
    -Owner       'my-org' `
    -Repo        'Infrastructure-E2E' `
    -Environment 'e2e-workstation'

if ($null -ne $deployment) {
    Set-DeploymentStatus -Token $token -Owner 'my-org' -Repo 'Infrastructure-E2E' `
        -DeploymentId $deployment.id -State 'in_progress'
}
```

---

### `Invoke-GitHubApi`

General-purpose GitHub REST API caller. Sets `Authorization: Bearer`,
`User-Agent: Infrastructure`, and `Content-Type: application/json` on
every request.

| Parameter | Type      | Required | Description                                         |
|-----------|-----------|----------|-----------------------------------------------------|
| `-Token`  | string    | Yes      | Bearer token - PAT or GitHub App installation token |
| `-Uri`    | string    | Yes      | Full GitHub API URI                                 |
| `-Method` | string    | No       | HTTP method; defaults to `'Get'`                    |
| `-Body`   | hashtable | No       | Request body; serialized to JSON automatically      |

Returns the raw `Invoke-RestMethod` response.

```powershell
# GET - list runners
$runners = Invoke-GitHubApi -Token $token `
    -Uri 'https://api.github.com/repos/owner/repo/actions/runners'

# POST - create a deployment
$deployment = Invoke-GitHubApi -Token $token `
    -Uri 'https://api.github.com/repos/owner/repo/deployments' `
    -Method 'Post' `
    -Body @{ ref = 'master'; environment = 'e2e-workstation'; auto_merge = $false }
```

---

### `Invoke-ModuleInstall`

Installs a module from PSGallery if absent or below the minimum required
version, then imports it.

| Parameter        | Type    | Required | Description                                                     |
|------------------|---------|----------|-----------------------------------------------------------------|
| `-ModuleName`    | string  | Yes      | The module to install and import                                 |
| `-MinimumVersion`| Version | No       | Minimum acceptable version; any installed version accepted if omitted |

```powershell
# Install with a minimum version constraint
Invoke-ModuleInstall -ModuleName 'Infrastructure.Secrets' -MinimumVersion '1.2.0'

# Install if absent, accept any version
Invoke-ModuleInstall -ModuleName 'Posh-SSH'
```

---

### `Invoke-SshClientCommand`

Runs a shell command on a remote host via an SSH.NET `SshClient` instance
and returns a normalised result object.

Requires Posh-SSH to be installed first so its bundled `Renci.SshNet.dll`
is loaded into the session before a client is constructed.

| Parameter    | Type   | Required | Description                                    |
|--------------|--------|----------|------------------------------------------------|
| `-SshClient` | object | Yes      | A connected `Renci.SshNet.SshClient` instance  |
| `-Command`   | string | Yes      | Shell command to run on the remote host        |

Returns a `PSCustomObject` with:

| Property     | Type   | Description                               |
|--------------|--------|-------------------------------------------|
| `Output`     | string | Stdout from the command (`Result`)        |
| `Error`      | string | Stderr from the command                   |
| `ExitStatus` | int    | Exit code (0 = success, non-zero = error) |

```powershell
$r = Invoke-SshClientCommand -SshClient $sshClient -Command "getent group docker"
if ($r.ExitStatus -ne 0) { throw "Command failed: $($r.Error)" }
$r.Output
```

---

### `Set-DeploymentStatus`

Posts a status update to an existing GitHub deployment. Wraps
`POST /repos/{owner}/{repo}/deployments/{id}/statuses`.

| Parameter        | Type   | Required | Description                                                   |
|------------------|--------|----------|---------------------------------------------------------------|
| `-Token`         | string | Yes      | Bearer token - PAT or GitHub App installation token           |
| `-Owner`         | string | Yes      | GitHub organisation or user that owns the repo                |
| `-Repo`          | string | Yes      | Repository name (without the owner prefix)                    |
| `-DeploymentId`  | int    | Yes      | Numeric deployment ID (from `Get-PendingDeployment`)          |
| `-State`         | string | Yes      | Deployment state: `error`, `failure`, `inactive`, `in_progress`, `queued`, `pending`, `success` |
| `-Description`   | string | No       | Human-readable description shown in the GitHub UI             |
| `-LogUrl`        | string | No       | URL to job logs; shown as a link in the GitHub UI             |

```powershell
# Mark as in progress when work begins
Set-DeploymentStatus -Token $token -Owner 'my-org' -Repo 'Infrastructure-E2E' `
    -DeploymentId $deployment.id -State 'in_progress' -Description 'E2E tests running'

# Mark as success or failure when tests finish
Set-DeploymentStatus -Token $token -Owner 'my-org' -Repo 'Infrastructure-E2E' `
    -DeploymentId $deployment.id -State 'success' `
    -Description 'All E2E tests passed' -LogUrl 'https://github.com/my-org/Infrastructure-E2E/actions/runs/123'
```

---

## Repo structure

```
Infrastructure-Common/
|- Infrastructure.Common/
|  |- Public/
|  |  |- Assert-RequiredProperties.ps1
|  |  |- Get-GitHubAppToken.ps1
|  |  |- Get-PendingDeployment.ps1
|  |  |- Invoke-GitHubApi.ps1
|  |  |- Invoke-ModuleInstall.ps1
|  |  |- Set-DeploymentStatus.ps1
|  |  `- Invoke-SshClientCommand.ps1
|  |- Infrastructure.Common.psm1        # Dot-sources Public\ and exports functions
|  `- Infrastructure.Common.psd1        # Module manifest (version, GUID, exports)
|- Tests/
|  |- Assert-RequiredProperties.Tests.ps1
|  |- Get-GitHubAppToken.Tests.ps1
|  |- Get-PendingDeployment.Tests.ps1
|  |- Invoke-GitHubApi.Tests.ps1
|  |- Invoke-ModuleInstall.Tests.ps1
|  |- Set-DeploymentStatus.Tests.ps1
|  |- Invoke-SshClientCommand.Tests.ps1
|  `- Integration/                      # Integration tests - run in Docker only
|- .github/
|  |- actions/
|  |  |- tag-from-manifest/
|  |  |  |- action.yml                  # Creates git tag from manifest version
|  |  |  `- Invoke-TagFromManifest.ps1
|  |  |- run-unit-tests/
|  |  |  |- action.yml                  # Reusable composite action for unit tests
|  |  |  `- Run-Tests.ps1              # Canonical unit test runner implementation
|  |  `- run-integration-tests/
|  |     |- action.yml                  # Reusable composite action for integration tests
|  |     `- Run-IntegrationTests.ps1   # Canonical integration test runner implementation
|  `- workflows/
|     |- ci-powershell.yml        # Shared unit test workflow - reusable by other repos
|     |- ci-powershell-docker.yml # Shared integration test workflow - reusable by other repos
|     |- tag.yml                  # Fires on manifest change - runs CI then tags and publishes
|     `- publish.yml              # Reusable publish workflow - called by tag.yml
|- Install.ps1               # Installs from source for local development
|- Publish.ps1               # Publishes to PSGallery (called by publish.yml)
|- Run-Tests.ps1             # Runs unit tests locally (thin wrapper)
|- Run-IntegrationTests.ps1  # Runs integration tests locally in Docker (thin wrapper)
`- README.md
```
