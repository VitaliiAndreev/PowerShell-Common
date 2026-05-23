# Problem: retry logic is duplicated and not composable

## Index
- [Context](#context)
- [Problems with the current approach](#problems-with-the-current-approach)
- [What we want instead](#what-we-want-instead)
- [Scope](#scope)

---

## Context

Two repositories currently implement their own retry loops, each tailored to a
different transient-failure class:

| Repo | Function | Retries on | Backoff |
|---|---|---|---|
| Infrastructure-Common | [`Invoke-WithNetworkRetry`](../../../../Infrastructure.Common/Public/Invoke-WithNetworkRetry.ps1) | transient network exceptions (`HttpRequestException`, `SocketException`, 5xx `HttpResponseException`, timeouts) | exponential, unbounded growth |
| Infrastructure-Vm-Provisioner | `Remove-ItemWithRetry` in [`remove-vm.ps1`](../../../../../Infrastructure-Vm-Provisioner/hyper-v/ubuntu/down/vm/remove-vm.ps1) | `System.IO.IOException` (VMMS file-handle release after `Remove-VM`) | exponential, capped at `MaxIntervalSeconds` |

Both loops share the same shape:

1. Attempt the operation.
2. Catch and classify the error - retry only on a known transient class.
3. Sleep with exponential backoff between attempts.
4. After `MaxAttempts`, rethrow the original failure.

The only things that differ are **which exceptions count as transient** and the
**caller-friendly logging text**.

## Problems with the current approach

**Duplicated backoff loop**
Two near-identical `for` loops, two `Start-Sleep` calls, two off-by-one
guards against sleeping after the final attempt. Future fixes (jitter, a
deadline budget, a structured retry log) would need to land in both places.

**No reuse outside the two known cases**
Any other site that needs retry behaviour - SSH handshakes, transient
PowerShell remoting errors, eventually-consistent cloud APIs - has to either
copy one of these loops or fall back to the wrong classifier. The
network-retry function silently passes IOException through; the file-lock
retry silently passes network errors through.

**No way to compose classifiers**
A real provisioning step often does several things in sequence (download a
tarball, then write it to disk, then chmod it) where *different* errors are
transient at *different* moments. Today the caller must wrap each sub-step in
the matching helper. A single retry around the whole step is not expressible.

**File-lock helper is buried in a VM-specific script**
`Remove-ItemWithRetry` sits next to `Invoke-VmRemoval` in
Infrastructure-Vm-Provisioner. It has nothing VM-specific in it - it deletes
files - but its location prevents any other repo from finding it.

## What we want instead

A single generic primitive in `Infrastructure.Common`, paired with
hashtable-based strategy factories that supply the classifier and the
backoff curve:

```
Infrastructure.Common/Public/Retry/
  Invoke-WithRetry.ps1                         (NEW) generic loop
  Invoke-WithNetworkRetry.ps1                  (REMOVED, see Step 4)
  TransientErrorStrategies/
    New-TransientNetworkRetryStrategy.ps1      (NEW) classifier factory
    New-FileLockRetryStrategy.ps1              (NEW) classifier factory
  BackoffStrategies/
    New-ExponentialBackoffStrategy.ps1         (NEW) backoff factory
    New-LinearBackoffStrategy.ps1              (NEW) backoff factory
    New-ConstantBackoffStrategy.ps1            (NEW) backoff factory
    New-CustomBackoffStrategy.ps1              (NEW) backoff escape hatch
```

The retry family lives in its own subtree because it is the first group
large enough to warrant grouping, and it is subdivided by strategy
category (`TransientErrorStrategies/`, `BackoffStrategies/`) so neither
folder grows past a handful of files. Loop entry points stay at the
`Retry/` root because they consume strategies rather than being one. See
[plan.md](plan.md#folder-layout) for the convention.

`Invoke-WithRetry` accepts a `[hashtable[]] -RetryStrategy` (OR-composed
classifiers, each shaped `@{ Name; ShouldRetry }`) and a single
`[hashtable] -BackoffStrategy` (shaped `@{ Name; GetDelay }`) plus
`-ScriptBlock`, `-MaxAttempts`, and `-OperationName`. Composition is by
passing multiple strategies into `-RetryStrategy`: any predicate returning
`$true` triggers a retry, which lets a single call site cover both network
blips and file locks when the operation legitimately touches both.

Strategy hashtables are deliberate: no PowerShell `class`es, so factories
compose cleanly across modules, serialise trivially in tests, and require
no type-import dance for consumers. See [plan.md](plan.md#strategy-shape)
for the exact contract.

`Invoke-WithNetworkRetry` is removed rather than refactored into a
wrapper - its two current call sites in Infrastructure-Vm-Provisioner
migrate to `Invoke-WithRetry` with `New-TransientNetworkRetryStrategy`,
keeping the public surface to a single retry entry point. The
`Test-TransientNetworkException` policy moves alongside the new factory as
a file-private helper.

`Remove-ItemWithRetry` in Infrastructure-Vm-Provisioner is replaced by a
direct call to `Invoke-WithRetry` with `New-FileLockRetryStrategy` (after
the consumer bumps its `Infrastructure.Common` minimum version).

## Scope

**Infrastructure.Common** (this repo):
- New `Invoke-WithRetry` generic primitive consuming hashtable strategies.
- New retry-strategy factories (`New-TransientNetworkRetryStrategy`,
  `New-FileLockRetryStrategy`).
- New backoff-strategy factories (exponential, linear, constant, custom).
- `Invoke-WithNetworkRetry` removed (its classifier policy lives next to
  `New-TransientNetworkRetryStrategy` as a file-private helper).
- Tests for each new factory and for the loop, including strategy
  composition.
- Major version bump (5.0.0) - removing a public function is a breaking
  change.

**Infrastructure-Vm-Provisioner** (consumer):
- `Remove-ItemWithRetry` deleted from
  [`remove-vm.ps1`](../../../../../Infrastructure-Vm-Provisioner/hyper-v/ubuntu/down/vm/remove-vm.ps1);
  call site uses `Invoke-WithRetry` with `New-FileLockRetryStrategy`.
- `Invoke-WithNetworkRetry` call sites in JDK acquisition switch to
  `Invoke-WithRetry` with `New-TransientNetworkRetryStrategy`.
- Bumps minimum `Infrastructure.Common` version to `5.0.0` in its module
  install step.

**Out of scope** (deliberately):
- Jitter, deadline budgets, circuit-breaker logic. Plain exponential backoff
  with a cap is enough for the two known cases; richer policies can be added
  later without breaking the surface.
- Retrying based on return values (e.g. "retry if result is null"). All
  current call sites signal failure by throwing.
