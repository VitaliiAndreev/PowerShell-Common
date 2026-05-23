# Plan: Add Invoke-SshClientCommand to Infrastructure.Common

## Index

- [Step 1 - Add the function and tests, bump version to 1.2.0](#step-1)
- [Step 2 - Update Infrastructure-Vm-Users to consume the shared function](#step-2)

---

## Step 1

**Add `Invoke-SshClientCommand`, unit tests, and bump module version to 1.2.0.**

Reason: all module changes ship together - a single committable unit that
keeps the module and its tests in sync. The version bump is required so
consumer repos can pin `MinimumVersion '1.2.0'` to guarantee the function
is available.

### Files changed

| File | Change |
|---|---|
| `Infrastructure.Common\Public\Invoke-SshClientCommand.ps1` | New - function definition |
| `Infrastructure.Common\Infrastructure.Common.psm1` | Add dot-source and export |
| `Infrastructure.Common\Infrastructure.Common.psd1` | Bump version 1.1.0 -> 1.2.0, add to FunctionsToExport |
| `Tests\Invoke-SshClientCommand.Tests.ps1` | New - unit tests |
| `README.md` | Document the new function |

### Tests

`Tests\Invoke-SshClientCommand.Tests.ps1` - unit tests only (no SSH.NET
dependency). The fake `$SshClient` is a `PSCustomObject` with a
`RunCommand` script method, so tests run without Posh-SSH installed.

Scenarios:

- Returns `.Output` mapped from `$cmd.Result`
- Returns `.Error` mapped from `$cmd.Error`
- Returns `.ExitStatus` mapped from `$cmd.ExitStatus`
- Passes `$Command` string verbatim to `RunCommand`
- Works for exit status 0 (success) and non-zero (failure)

---

## Step 2

**Update `Infrastructure-Vm-Users` to use the shared function.**

Reason: removes the duplicate local definition and proves the shared
function works end-to-end through CI. Other repos that add SSH in the
future follow the same pattern documented here.

### Files changed (in `Infrastructure-Vm-Users`)

| File | Change |
|---|---|
| `hyper-v\ubuntu\common.ps1` | Remove `Invoke-SshClientCommand` definition |
| `hyper-v\ubuntu\create-users.ps1` | Bump `MinimumVersion` to `'1.2.0'` |
| `README.md` | Update prerequisites - note `Invoke-SshClientCommand` comes from the module |

No test changes are needed: the unit tests already stub `Invoke-SshClientCommand`
as a mock (they do not dot-source `common.ps1`). The integration test
dot-sources `common.ps1` and then the function comes from the module because
the module is loaded before `common.ps1` is sourced - the definition in
`common.ps1` will simply be gone.
