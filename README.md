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
  - Top-level utilities
    - [Assert-RequiredProperties](#assert-requiredproperties)
    - [ConvertTo-Array](#convertto-array)
    - [Invoke-ModuleInstall](#invoke-moduleinstall)
  - Retry (`Public/Retry/`)
    - Loop
      - [Invoke-WithRetry](#invoke-withretry)
    - Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)
      - [New-TransientNetworkRetryStrategy](#new-transientnetworkretrystrategy)
      - [New-FileLockRetryStrategy](#new-filelockretrystrategy)
    - Backoff strategies (`Public/Retry/BackoffStrategies/`)
      - [New-ExponentialBackoffStrategy](#new-exponentialbackoffstrategy)
      - [New-LinearBackoffStrategy](#new-linearbackoffstrategy)
      - [New-ConstantBackoffStrategy](#new-constantbackoffstrategy)
      - [New-CustomBackoffStrategy](#new-custombackoffstrategy)
- [Reusable CI](#reusable-ci)
- [Repo structure](#repo-structure)

---

## Requirements

PowerShell 7+ (`pwsh`). Windows PowerShell 5.1 is not supported.

---

## Overview

Provides cross-cutting utilities used by all infrastructure repos so the logic
does not need to be duplicated and tested in each one independently. Functions
are grouped on disk by concern; the retry family lives under
`Public/Retry/`.

**Top-level utilities**
- **`Assert-RequiredProperties`** - validates that a PSCustomObject has all
  required properties present and non-empty; collects every violation before
  throwing so the consumer sees the full picture in one run.
- **`ConvertTo-Array`** - ensures a value is always an array regardless of
  whether PowerShell unrolled a single-item collection.
- **`Invoke-ModuleInstall`** - installs a module from PSGallery if absent or
  below the required minimum version, then imports it.

**Retry (`Public/Retry/`)** - subdivided by strategy category so each
folder stays small as more factories land:

- *Loop (root of `Public/Retry/`)*
  - **`Invoke-WithRetry`** - generic retry loop. Consumes hashtable-shaped
    retry strategies (`ShouldRetry` classifiers) and a backoff strategy
    (`GetDelay` provider). Multiple retry strategies are OR-composed so a
    single call can cover several legitimately-transient failure classes
    (e.g. network + file-lock). Defaults to exponential backoff when none
    is supplied.
- *Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)* - factories that
  return `@{ Name; ShouldRetry }` classifiers consumed by
  `Invoke-WithRetry`. Compose multiple via `-RetryStrategy`
  when a single call legitimately touches several transient-failure
  classes (e.g. network + file-lock).
  - **`New-TransientNetworkRetryStrategy`** - matches DNS/socket/5xx.
  - **`New-FileLockRetryStrategy`** - matches `System.IO.IOException`
    (Hyper-V VMMS handle-release case).
- *Backoff strategies (`Public/Retry/BackoffStrategies/`)* - factories
  that return `@{ Name; GetDelay }` providers consumed by
  `Invoke-WithRetry` via `-BackoffStrategy`. Pick the curve that
  matches the underlying failure; reach for `New-CustomBackoffStrategy`
  when the built-ins do not (HTTP 429 `Retry-After`, jittered
  exponential, deadline-aware backoff, ...).
  - **`New-ExponentialBackoffStrategy`** - doubles each attempt up to a
    cap. Sensible default for most call sites.
  - **`New-LinearBackoffStrategy`** - grows linearly per attempt up to
    a cap. Predictable spacing when exponential ramps up too fast.
  - **`New-ConstantBackoffStrategy`** - same delay every attempt. Use
    when the failure has a known fixed recovery window.
  - **`New-CustomBackoffStrategy`** - wraps a caller-supplied
    `GetDelay` script block in the standard hashtable shape.

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

Functions are grouped on disk by concern. Top-level utilities sit at the
root of `Public/`; the retry family lives under `Public/Retry/` and is
further subdivided into `TransientErrorStrategies/` and (in a later
step) `BackoffStrategies/`.

### Top-level utilities

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

### Retry (`Public/Retry/`)

#### Loop

### `Invoke-WithRetry`

Generic retry loop. The classification of "what counts as retryable" is
supplied by hashtable-shaped retry strategies (`ShouldRetry`
predicates); the inter-attempt pacing comes from a backoff strategy
(`GetDelay` provider). Multiple retry strategies are OR-composed: if
any predicate returns `$true`, the loop retries; if none match, the
failure propagates immediately. The matched strategy's `Name` is
surfaced in the per-retry warning so operators can tell which policy
fired when several are composed.

`-BackoffStrategy` defaults to `New-ExponentialBackoffStrategy`
(2s -> 4s -> 8s, capped at 30s) because that policy fits both currently
known call sites (HTTP + file-lock); callers wanting a different curve
pass one explicitly.

| Parameter         | Type          | Required | Description                                                                                  |
|-------------------|---------------|----------|----------------------------------------------------------------------------------------------|
| `-ScriptBlock`    | scriptblock   | Yes      | The work to attempt. Its return value is the function's return value on success.             |
| `-RetryStrategy`  | hashtable[]   | Yes      | One or more `@{ Name; ShouldRetry }` strategies. Mandatory so "never retries" cannot happen silently. |
| `-BackoffStrategy`| hashtable     | No       | A `@{ Name; GetDelay }` strategy. Defaults to `New-ExponentialBackoffStrategy`.              |
| `-MaxAttempts`    | int           | No       | Total attempts including the first. Defaults to `3`. Pass `1` to disable retry.              |
| `-OperationName`  | string        | No       | Label surfaced in the per-retry warning. Defaults to `operation`.                            |

```powershell
# Network call with default exponential backoff.
$json = Invoke-WithRetry `
    -OperationName 'Adoptium release lookup' `
    -RetryStrategy (New-TransientNetworkRetryStrategy) `
    -ScriptBlock   { Invoke-RestMethod $uri }

# File-lock with a tighter attempt budget.
Invoke-WithRetry `
    -OperationName 'delete VHDX' `
    -RetryStrategy (New-FileLockRetryStrategy) `
    -MaxAttempts   5 `
    -ScriptBlock   { Remove-Item $vhdxPath -Force -ErrorAction Stop }
```

---

#### Transient-error strategies (`Public/Retry/TransientErrorStrategies/`)

### `New-TransientNetworkRetryStrategy`

Builds a retry-strategy hashtable matching transient network failures
(DNS hiccups, connection drops, 5xx responses, HttpClient timeouts) for
use with `Invoke-WithRetry`. 4xx HttpResponseExceptions and non-network
errors are treated as permanent so failures stay fast.

Takes no parameters. Returns:

```powershell
@{
    Name        = 'TransientNetwork'
    ShouldRetry = { param($ErrorRecord) <bool> }
}
```

```powershell
Invoke-WithRetry `
    -ScriptBlock   { Invoke-RestMethod $uri } `
    -RetryStrategy (New-TransientNetworkRetryStrategy)
```

---

### `New-FileLockRetryStrategy`

Builds a retry-strategy hashtable matching `System.IO.IOException`
anywhere in the exception chain - the canonical Hyper-V VMMS
handle-release case where `Remove-Item` briefly fails after `Remove-VM`.
`UnauthorizedAccessException` is intentionally **not** matched: ACL
problems will not resolve on their own, and retrying just stalls the
caller before the real error surfaces.

Takes no parameters. Returns:

```powershell
@{
    Name        = 'FileLock'
    ShouldRetry = { param($ErrorRecord) <bool> }
}
```

```powershell
Invoke-WithRetry `
    -ScriptBlock   { Remove-Item -Path $vhdxPath -Force -ErrorAction Stop } `
    -RetryStrategy (New-FileLockRetryStrategy) `
    -MaxAttempts   5
```

---

#### Backoff strategies (`Public/Retry/BackoffStrategies/`)

All four factories return the same hashtable shape consumed by
`Invoke-WithRetry` via `-BackoffStrategy`:

```powershell
@{
    Name     = '<curve name>'
    GetDelay = { param($Attempt, $LastError) <seconds> }
}
```

`GetDelay` receives the current attempt number (1-based) and the most
recent `ErrorRecord` so custom providers can adapt the delay to the
failure (HTTP 429 `Retry-After`, deadline-aware backoff, ...).

### `New-ExponentialBackoffStrategy`

Doubles the delay each attempt, capped at a configurable ceiling.
Formula: `delay = min(InitialDelaySeconds * 2^(Attempt - 1), MaxIntervalSeconds)`.
Defaults (2s initial, 30s cap) suit the currently known call sites
(HTTP + file-lock).

| Parameter              | Type | Required | Description                                  |
|------------------------|------|----------|----------------------------------------------|
| `-InitialDelaySeconds` | int  | No       | Seconds before the first retry. Default `2`. |
| `-MaxIntervalSeconds`  | int  | No       | Upper bound per attempt. Default `30`.       |

```powershell
$backoff = New-ExponentialBackoffStrategy -InitialDelaySeconds 1 -MaxIntervalSeconds 10
```

---

### `New-LinearBackoffStrategy`

Grows the delay linearly per attempt up to a cap.
Formula: `delay = min(StepSeconds * Attempt, MaxIntervalSeconds)`.

| Parameter             | Type | Required | Description                                  |
|-----------------------|------|----------|----------------------------------------------|
| `-StepSeconds`        | int  | No       | Increment per attempt. Default `2`.          |
| `-MaxIntervalSeconds` | int  | No       | Upper bound per attempt. Default `30`.       |

```powershell
$backoff = New-LinearBackoffStrategy -StepSeconds 2 -MaxIntervalSeconds 10
# Delays: 2, 4, 6, 8, 10, 10, ...
```

---

### `New-ConstantBackoffStrategy`

Returns the same delay on every attempt. Use when the failure has a
known fixed recovery window (service restart cycle, fixed lease
renewal, ...) and exponential growth would just oversleep.

| Parameter       | Type | Required | Description                          |
|-----------------|------|----------|--------------------------------------|
| `-DelaySeconds` | int  | No       | Delay returned every call. Default `2`. |

```powershell
$backoff = New-ConstantBackoffStrategy -DelaySeconds 5
```

---

### `New-CustomBackoffStrategy`

Wraps a caller-supplied `GetDelay` script block in the standard
backoff-strategy hashtable shape. Escape hatch for cases the built-ins
do not cover (HTTP 429 `Retry-After`, jittered exponential,
deadline-aware backoff).

| Parameter        | Type        | Required | Description                                                                |
|------------------|-------------|----------|----------------------------------------------------------------------------|
| `-DelayProvider` | scriptblock | Yes      | Called as `& $DelayProvider $Attempt $LastError`; must return seconds.     |
| `-Name`          | string      | No       | Label surfaced by `Invoke-WithRetry` in the per-retry warning. Default `Custom`. |

```powershell
$jittered = New-CustomBackoffStrategy -Name 'JitteredExponential' `
    -DelayProvider {
        param($Attempt, $LastError)
        $base = [Math]::Min(2 * [Math]::Pow(2, $Attempt - 1), 30)
        $base + (Get-Random -Minimum 0 -Maximum 2)
    }
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
|  |- Private/                          # Module-internal helpers (not exported); mirrors Public\ layout
|  |  `- Retry/
|  |     `- Assert-RetryStrategyShape.ps1
|  |- Public/
|  |  |- Assert-RequiredProperties.ps1
|  |  |- ConvertTo-Array.ps1
|  |  |- Invoke-ModuleInstall.ps1
|  |  `- Retry/                         # Retry family (loop + strategies)
|  |     |- Invoke-WithRetry.ps1             # generic retry loop
|  |     |- TransientErrorStrategies/       # ShouldRetry classifiers
|  |     |  |- New-FileLockRetryStrategy.ps1
|  |     |  `- New-TransientNetworkRetryStrategy.ps1
|  |     `- BackoffStrategies/              # GetDelay providers
|  |        |- New-ConstantBackoffStrategy.ps1
|  |        |- New-CustomBackoffStrategy.ps1
|  |        |- New-ExponentialBackoffStrategy.ps1
|  |        `- New-LinearBackoffStrategy.ps1
|  |- Infrastructure.Common.psm1        # Dot-sources Public\ (recursively); exports Public functions
|  `- Infrastructure.Common.psd1        # Module manifest (version, GUID, exports)
|- Tests/
|  |- Assert-RequiredProperties.Tests.ps1
|  |- ConvertTo-Array.Tests.ps1
|  |- Invoke-ModuleInstall.Tests.ps1
|  |- Retry/                            # Mirrors Infrastructure.Common\Public\Retry\
|  |  |- Invoke-WithRetry.Tests.ps1
|  |  |- TransientErrorStrategies/
|  |  |  |- New-FileLockRetryStrategy.Tests.ps1
|  |  |  `- New-TransientNetworkRetryStrategy.Tests.ps1
|  |  `- BackoffStrategies/
|  |     |- New-ConstantBackoffStrategy.Tests.ps1
|  |     |- New-CustomBackoffStrategy.Tests.ps1
|  |     |- New-ExponentialBackoffStrategy.Tests.ps1
|  |     `- New-LinearBackoffStrategy.Tests.ps1
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
