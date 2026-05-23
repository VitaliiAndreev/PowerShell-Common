# Problem: Drop PowerShell 5.1 Support

## Index

- [Context](#context)
- [What Is Changing](#what-is-changing)
- [Why Now](#why-now)
- [Affected Components](#affected-components)
- [Out of Scope](#out-of-scope)

---

## Context

The module manifest (`Infrastructure.Common.psd1`) currently declares:

```powershell
PowerShellVersion = '5.1'
```

However:

- `Get-GitHubAppToken` uses `RSA.ImportFromPem()`, a .NET 5+ API unavailable in 5.1.
- Integration tests already run exclusively on PowerShell 7 (Docker, Linux).
- The CI workflow (`ci-powershell.yml`) runs unit tests on **both** 5.1 and 7, adding
  a job that cannot meaningfully validate the module on its declared minimum.
- No `CompatiblePSEditions` is declared; PSGallery treats the module as Windows-only
  5.1-compatible, which is incorrect.

---

## What Is Changing

| Area | Current state | Target state |
|------|--------------|--------------|
| `Infrastructure.Common.psd1` | `PowerShellVersion = '5.1'`, no `CompatiblePSEditions` | `PowerShellVersion = '7.0'`, `CompatiblePSEditions = @('Core')` |
| `ci-powershell.yml` | Two jobs: `ci-ps51` (PowerShell 5.1) and `ci-ps7` (PowerShell 7) | One job: `ci-ps7` only |
| `Assert-RequiredProperties.ps1` | Uses `Get-Member -MemberType NoteProperty` (chosen for 5.1 compat) | `$Object.PSObject.Properties.Name` (idiomatic PS 7) |
| `Assert-RequiredProperties.ps1` | Three comments referencing "PS 5.1" | Comments updated or removed |
| `README.md` | States "PowerShell 5.1+" in requirements | States "PowerShell 7+" |

The `[string]$value` cast before `IsNullOrWhiteSpace` in `Assert-RequiredProperties` is
**not** a 5.1 compromise - `IsNullOrWhiteSpace` requires a `string` argument in both
versions - so it is unchanged.

---

## Why Now

- The 5.1 CI job has always been a false signal: tests pass on 5.1 only because the
  code paths exercised by unit tests (mocked) avoid the 7-only APIs.
- Declaring `PSEdition = Core` enables PSGallery to surface the module correctly to 7
  users and suppress it for 5.1 users who cannot run it.
- Removing the dead CI job reduces feedback time and eliminates confusion for future
  contributors.

---

## Out of Scope

- `Get-GitHubAppToken.ps1` comment ("Requires PowerShell 7+") - already accurate, no change.
- No `#Requires` directives exist anywhere in the codebase.
- No `$PSVersionTable` version-branch code exists anywhere.
- No test logic changes - tests are already PS 7-compatible.
- No change to the `[string]$value` cast in `Assert-RequiredProperties` (still needed).
