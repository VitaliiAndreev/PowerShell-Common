# Problem: Host-to-VM File Transfer

## Index
- [Context](#context)
- [Problems with the current approach](#problems-with-the-current-approach)
- [What we want instead](#what-we-want-instead)
- [Scope](#scope)
- [For the non-technical reader](#for-the-non-technical-reader)

---

## Context

VMs provisioned on this workstation connect to the internet via a Hyper-V NAT,
which is throttled to ~116 KB/s. The Windows host has normal internet access.
The host and all VMs share a fast internal Hyper-V switch (E2E-VmLAN) with no
internet dependency.

Two places in the codebase currently need to get a large file into a VM:

| Call site | File | How | Problem |
|---|---|---|---|
| `Invoke-TarballDownload` (GitHubRunners) | 225 MB runner binary | `curl` from GitHub, inside VM | slow NAT, no-internet failure |
| `Copy-RunnerTarballToVm` (E2E) | same file | one-shot raw TCP server per call | ephemeral, firewall churn, not reusable |

## Problems with the current approach

**`Invoke-TarballDownload` (`curl` from GitHub inside the VM)**
- Downloads over the Hyper-V NAT at ~116 KB/s - a 225 MB file takes ~30 min.
- Fails entirely when the VM has no internet (e.g. during early cloud-init).
- Couples runner registration to GitHub availability.

**`Copy-RunnerTarballToVm` (one-shot TCP server)**
- A new background PS process and firewall rule are created per transfer, then
  torn down. Startup adds latency and the firewall churn is unnecessary noise.
- Raw TCP with no protocol structure - works for one file, but extending to
  multiple files or concurrent VMs requires redesign.
- Lives in the E2E repo; the production runner registration path has no
  equivalent, so it still uses the slow `curl` path.

## What we want instead

A persistent HTTP file server running on the Windows host, bound to the
internal Hyper-V switch, that:

- Starts once at the beginning of a session (provisioning or runner
  registration) and stops when the session ends.
- Serves files from a host-side staging directory over plain HTTP.
- Requires one permanent firewall rule for the session, not one per file.
- Is reachable from all VMs on the switch via `curl` - no additional tooling
  needed in the guest (curl is pre-installed on Ubuntu cloud images).
- Can serve any file, not just the runner tarball.

`Invoke-TarballDownload` is updated to pull from the host server instead of
GitHub. `Copy-RunnerTarballToVm` is replaced by staging the file on the host
and letting the VM fetch it.

## Scope

**Infrastructure.Common** (this repo) - new shared helpers:
- `Start-VmFileServer` - binds HttpListener to the switch IP, opens firewall
  rule, returns a server handle.
- `Stop-VmFileServer` - closes the listener and removes the firewall rule.
- `Add-VmFileServerFile` - stages a file for serving (idempotent, host-side
  copy/link into the server's directory).

**Infrastructure-GitHubRunners** - modified:
- `Invoke-TarballDownload` - pull from host server URL instead of GitHub.
- `register-runners.ps1` - start/stop the file server around the VM loop.

**Infrastructure-E2E** - modified:
- `Copy-RunnerTarballToVm` - replace one-shot TCP with a `curl` call to the
  already-running host server.
- `Invoke-RunnerLifecycleTest.ps1` - start/stop the file server around the
  lifecycle steps.
