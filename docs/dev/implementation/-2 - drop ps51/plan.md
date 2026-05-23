# Plan: Drop PowerShell 5.1 Support

See [problem.md](problem.md) for context and scope.

## Index

- [Step 1 - Clean up Assert-RequiredProperties.ps1](#step-1)
- [Step 2 - Update manifest, CI, and docs](#step-2)

---

## Step 1

**Remove the PS 5.1 compatibility shim from `Assert-RequiredProperties` and
confirm existing tests still pass.**

Reason: the `Get-Member` call was chosen specifically to work around PS 5.1
behaviour. Replacing it with `$Object.PSObject.Properties.Name` is the
idiomatic PS 7 form and removes the only production code change in this
feature. Keeping this as its own commit makes the refactor reviewable in
isolation from the config changes in Step 2.

### Files changed

| File | Change |
|---|---|
| `Infrastructure.Common/Public/Assert-RequiredProperties.ps1` | Replace `Get-Member` call; remove three stale "PS 5.1" comments |

### Detail

Replace:

```powershell
# Get-Member -MemberType NoteProperty is the reliable way to enumerate
# properties created by ConvertFrom-Json in PS 5.1 and PS 7.
$members = (Get-Member -InputObject $Object -MemberType NoteProperty).Name
```

With:

```powershell
$members = $Object.PSObject.Properties.Name
```

Remove the inline comment on line 63 ("Numeric properties (e.g. cpuCount)
are [int] in PS 5.1") - the `[string]` cast is still required for
`IsNullOrWhiteSpace`, but the PS 5.1 rationale no longer applies.

Update the `.DESCRIPTION` doc-comment to remove "PS 5.1-compatible".

### Tests

No new tests - the existing `Tests/Assert-RequiredProperties.Tests.ps1`
covers all property-check scenarios and will detect any regression in the
refactored logic. Run the full unit test suite to confirm green.

---

## Step 2

**Update the module manifest, remove the PS 5.1 CI job, and update docs.**

Reason: dropping a supported PowerShell version is a breaking change for
any 5.1 consumer, so the manifest version must be bumped to signal that.
The CI job removal and README update are bundled here as they are all
config/docs with no logic - one reviewable, shippable commit.

### Files changed

| File | Change |
|---|---|
| `Infrastructure.Common/Infrastructure.Common.psd1` | `PowerShellVersion` 5.1 -> 7.0; add `CompatiblePSEditions = @('Core')`; bump `ModuleVersion` (breaking change - major bump recommended) |
| `.github/workflows/ci-powershell.yml` | Delete `ci-ps51` job entirely; keep `ci-ps7` unchanged |
| `README.md` | Update requirements to "PowerShell 7+" |

### Tests

No new tests. The `ci-ps7` job in `ci-powershell.yml` is the test: after
the commit, CI must run on PS 7 and pass. Verify locally with
`Run-Tests.ps1` under `pwsh` before pushing.
