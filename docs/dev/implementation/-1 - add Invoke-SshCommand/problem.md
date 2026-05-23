# Problem: Invoke-SshClientCommand is not shared

## Index

- [What is changing](#what-is-changing)
- [Why](#why)
- [What is not changing](#what-is-not-changing)

---

## What is changing

`Invoke-RemoteCommand` - a thin wrapper around SSH.NET's `SshClient.RunCommand()`
- currently lives in `Infrastructure-Vm-Users/hyper-v/ubuntu/common.ps1`. It will
be moved into this module as a first-class exported function and renamed to
`Invoke-SshClientCommand` to make the transport explicit.

The original function as it stands in the consumer repo:

```powershell
function Invoke-RemoteCommand {
    param([object] $SshClient, [string] $Command)
    $cmd = $SshClient.RunCommand($Command)
    [PSCustomObject]@{
        Output     = $cmd.Result
        Error      = $cmd.Error
        ExitStatus = $cmd.ExitStatus
    }
}
```

`$SshClient` is typed `[object]` deliberately - referencing the concrete
`Renci.SshNet.SshClient` type at module import time would fail because
Posh-SSH (which bundles SSH.NET) may not yet be loaded. Callers must load
Posh-SSH first.

---

## Why

Any infrastructure repo that SSH-es into VMs needs this wrapper. Without a
shared copy, each repo reimplements it or copies it - and risks rediscovering
the hard way that Posh-SSH 3.x `ConnectionInfoGenerator.GetCredConnectionInfo()`
drops algorithm entries from SSH.NET's `ConnectionInfo`, causing
"Key exchange negotiation failed" against OpenSSH 9.x (Ubuntu 24.04). The
fix - using SSH.NET directly and bypassing Posh-SSH cmdlets entirely - is
encoded in this function. Centralising it means the fix is inherited
automatically rather than stumbled upon independently in each repo.

---

## What is not changing

- The function signature and output shape are unchanged.
- `Infrastructure-Vm-Users/hyper-v/ubuntu/common.ps1` will drop the local
  definition once consumers are updated (tracked in that repo's plan).
- No other functions in this module are touched.

---
