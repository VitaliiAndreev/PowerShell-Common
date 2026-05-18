# Infrastructure-Common

Shared PowerShell module providing generic utilities for the
`Infrastructure-*` polyrepo family. Domain-specific helpers live in
sibling modules:

- [`Infrastructure.GitHub`](https://github.com/VitaliiAndreev/Infrastructure-GitHub) - GitHub API, deployments, runner binaries
- [`Infrastructure.HyperV`](https://github.com/VitaliiAndreev/Infrastructure-HyperV) - VM SSH execution, host file server

## Index

- [Requirements](#requirements)
- [Overview](#overview)
- [Installation](#installation)
- [Publishing](#publishing)
- [API reference](#api-reference)
  - [Assert-RequiredProperties](#assert-requiredproperties)
  - [ConvertTo-Array](#convertto-array)
  - [Invoke-ModuleInstall](#invoke-moduleinstall)
  - [Invoke-WithNetworkRetry](#invoke-withnetworkretry)
- [Reusable CI](#reusable-ci)
- [Repo structure](#repo-structure)

---

## Requirements

PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is not supported.

---

## Overview

Provides cross-cutting utilities used by all infrastructure repos so the logic
does not need to be duplicated and tested in each one independently:

- **`Assert-RequiredProperties`** - validates that a PSCustomObject has all
  required properties present and non-empty; collects every violation before
  throwing so the consumer sees the full picture in one run.
- **`ConvertTo-Array`** - ensures a value is always an array regardless of
  whether PowerShell unrolled a single-item collection.
- **`Invoke-ModuleInstall`** - installs a module from PSGallery if absent or
  below the required minimum version, then imports it.
- **`Invoke-WithNetworkRetry`** - runs a scriptblock and retries on transient
  network failures (DNS hiccups, connection drops, 5xx) with exponential
  backoff; non-transient errors (4xx, validation bugs, mock-thrown strings)
  propagate immediately so failures stay fast.

This repo is also the canonical home of the reusable CI workflows and composite
actions that every infrastructure module shares - see
[Reusable CI](#reusable-ci).

### Bootstrap note

`Invoke-ModuleInstall` cannot install itself. Each consumer script that needs
this module must include a short inline guard to install `Infrastructure.Common`
first - this is a one-time cost per script, and all other module installs then
flow through `Invoke-ModuleInstall`.

```powershell
# Inline bootstrap - cannot use Invoke-ModuleInstall to install itself.
$_common = Get-Module -ListAvailable -Name Infrastructure.Common |
    Sort-Object Version -Descending | Select-Object -First 1
if (-not $_common -or $_common.Version -lt [Version]'4.0.1') {
    Install-Module Infrastructure.Common -Scope CurrentUser -Force
    # Re-query so the comparison below uses the freshly installed version.
    $_common = Get-Module -ListAvailable -Name Infrastructure.Common |
        Sort-Object Version -Descending | Select-Object -First 1
}
# Reload only when the loaded state differs from the target (multiple
# versions live, or wrong version live). Mirrors the conditional in
# Invoke-ModuleInstall - inlined here because the bootstrap installs
# the very module that defines that function.
$_loaded = @(Get-Module -Name Infrastructure.Common)
if ($_loaded.Count -ne 1 -or $_loaded[0].Version -ne $_common.Version) {
    if ($_loaded) { $_loaded | Remove-Module -Force }
    Import-Module Infrastructure.Common -Force -ErrorAction Stop
}
```

---

## Installation

Consuming repos install automatically from PSGallery via the bootstrap block
above - no manual step needed.

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

### `ConvertTo-Array`

Wraps a value in a single-element array if PowerShell unrolled it down to a
scalar, and returns an existing array unchanged. Use after any pipeline or
`ConvertFrom-Json` call where a one-item result must still be enumerable.

| Parameter   | Type   | Required | Description                          |
|-------------|--------|----------|--------------------------------------|
| `-Value`    | object | Yes      | The value to normalise to an array   |

```powershell
$entries = ConvertTo-Array ($json | ConvertFrom-Json)
foreach ($entry in $entries) { ... }   # safe even when $json had one element
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
Invoke-ModuleInstall -ModuleName 'Pester' -MinimumVersion '5.0'

# Install if absent, accept any version
Invoke-ModuleInstall -ModuleName 'Posh-SSH'
```

---

### `Invoke-WithNetworkRetry`

Runs `-ScriptBlock` and retries on transient network failures with
exponential backoff. Used to harden any caller that touches the network
(JDK acquisition, GitHub API, runner registration, ...) against brief
DNS hiccups or short-lived 5xx responses without making hard failures
feel sluggish.

Classification is deliberate: failures are retried only when the
exception chain contains a known-transient type
(`HttpRequestException`, `SocketException`, `WebException`,
`TimeoutException`, `TaskCanceledException`) or a 5xx
`HttpResponseException`. Everything else (4xx, argument bugs, mock-
thrown strings in tests) propagates immediately.

| Parameter              | Type        | Required | Description                                                                         |
|------------------------|-------------|----------|-------------------------------------------------------------------------------------|
| `-ScriptBlock`         | scriptblock | Yes      | The work to attempt. Its return value is the function's return value on success.    |
| `-OperationName`       | string      | No       | Label surfaced in the per-retry warning. Defaults to `network call`.                |
| `-MaxAttempts`         | int         | No       | Total attempts including the first. Defaults to `3`. Pass `1` to disable retry.     |
| `-InitialDelaySeconds` | int         | No       | Seconds before the first retry. Doubles each subsequent attempt. Defaults to `2`.   |

```powershell
$json = Invoke-WithNetworkRetry `
    -OperationName 'Adoptium feature_releases lookup' `
    -ScriptBlock   { Invoke-RestMethod -Uri $uri -UseBasicParsing }
```

---

## Reusable CI

The composite actions under `.github/actions/` and the reusable workflows
under `.github/workflows/` are consumed by sibling repos
(`Infrastructure-GitHub`, `Infrastructure-HyperV`, `Infrastructure-Secrets`,
`Infrastructure-GitHubRunners`, ...). They are the canonical implementation;
sibling repos call them via `workflow_call` and `uses:` references to
`@master` rather than duplicating the logic.

| Reusable workflow | Purpose |
|---|---|
| `ci-powershell.yml` | Pester unit tests on Windows |
| `ci-powershell-docker-host.yml` | Pester integration tests inside a Docker container |
| `ci-powershell-docker-target.yml` | SSH integration tests against a Docker target |
| `tag.yml` | Creates a git tag from the manifest version |
| `publish.yml` | Publishes a module directory to PSGallery |

---

## Repo structure

```
Infrastructure-Common/
|- Infrastructure.Common/
|  |- Public/
|  |  |- Assert-RequiredProperties.ps1
|  |  |- ConvertTo-Array.ps1
|  |  |- Invoke-ModuleInstall.ps1
|  |  `- Invoke-WithNetworkRetry.ps1
|  |- Infrastructure.Common.psm1        # Dot-sources Public\; exports Public functions
|  `- Infrastructure.Common.psd1        # Module manifest (version, GUID, exports)
|- Tests/
|  |- Assert-RequiredProperties.Tests.ps1
|  |- ConvertTo-Array.Tests.ps1
|  |- Invoke-ModuleInstall.Tests.ps1
|  |- ... (shared CI helper tests)
|  `- Integration.DockerHost/           # Integration tests - run in Docker only
|- .github/
|  |- actions/                          # Reusable composite actions (canonical)
|  |  |- check-version-is-new/
|  |  |- tag-from-manifest/
|  |  |- run-unit-tests/
|  |  |- run-integration-tests/
|  |  |- run-ssh-integration-tests/
|  |  |- build-ssh-test-image/
|  |  |- scan-integration-tests/
|  |  |- assert-secret/
|  |  `- publish/
|  `- workflows/                        # Reusable workflows (canonical)
|     |- ci-powershell.yml
|     |- ci-powershell-docker-host.yml
|     |- ci-powershell-docker-target.yml
|     |- tag.yml
|     |- publish.yml
|     `- release.yml
|- Install.ps1               # Installs from source for local development
|- Publish.ps1               # Publishes to PSGallery (called by publish.yml)
|- Run-Tests.ps1             # Runs unit tests locally (thin wrapper)
|- Run-IntegrationTests-InDocker.ps1  # Runs integration tests locally in Docker
|- Run-IntegrationTests-AgainstDockerTarget.ps1
`- README.md
```
