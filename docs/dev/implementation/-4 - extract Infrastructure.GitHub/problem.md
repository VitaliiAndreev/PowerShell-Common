# Problem: Infrastructure.Common contains GitHub-specific functions

## Index
- [Context](#context)
- [Problems with the current approach](#problems-with-the-current-approach)
- [What we want instead](#what-we-want-instead)
- [Scope](#scope)
- [For the non-technical reader](#for-the-non-technical-reader)

---

## Context

`Infrastructure.Common` was created as a home for shared PowerShell utilities.
Over time, GitHub-specific functions have accumulated alongside genuinely
generic ones:

| Function | Nature |
|---|---|
| `Assert-RequiredProperties` | generic |
| `ConvertTo-Array` | generic |
| `Invoke-ModuleInstall` | generic |
| `Invoke-SshClientCommand` | generic |
| `Invoke-WithVmFileServer` | generic (Hyper-V) |
| `Add-VmFileServerFile` | generic (Hyper-V) |
| `Invoke-GitHubApi` | **GitHub-specific** |
| `Get-GitHubAppToken` | **GitHub-specific** |
| `Get-PendingDeployment` | **GitHub-specific** |
| `Set-DeploymentStatus` | **GitHub-specific** |
| `Invoke-RunnerTarballEnsure` | **GitHub-specific** |

The GitHub functions have no dependency on any other function in Common - they
depend only on standard PowerShell cmdlets. They are cohesive with each other
(all concern GitHub API interaction and GitHub Actions runner management) but
not with the SSH, file server, or utility functions they share a module with.

Every consumer repo that needs GitHub functions is forced to install all of
Common, including the Hyper-V file server and SSH primitives they may not need.

As the codebase grows, more consumer repos will need GitHub functionality -
deployment status reporting, token exchange, runner binary management - without
needing Hyper-V infrastructure. The coupling will get worse.

## Problems with the current approach

**Wrong cohesion boundary**
Functions that know about GitHub release URLs, GitHub App JWTs, and GitHub
deployment state live in the same module as SSH command execution and HTTP file
serving. These are unrelated concerns.

**Versioning is coarse**
A change to `Invoke-GitHubApi` forces a version bump of all of Common, requiring
all consumers to update regardless of whether they use GitHub functions at all.

**No independent publishability**
GitHub-specific functionality cannot be versioned, tested, or released on its
own schedule. A bug fix to `Get-GitHubAppToken` is coupled to the Common release
pipeline.

**Misplaced `Invoke-RunnerTarballEnsure`**
Added to Common in feature 05 as a quick reuse fix, it encodes GitHub Actions
runner naming conventions and release URL structure - domain knowledge that does
not belong in a generic utility module.

## What we want instead

A new `Infrastructure.GitHub` PowerShell module, published to PSGallery,
that owns all GitHub-specific functionality:

- GitHub API authentication (`Get-GitHubAppToken`, `Invoke-GitHubApi`)
- GitHub deployment lifecycle (`Get-PendingDeployment`, `Set-DeploymentStatus`)
- GitHub Actions runner binary management (`Invoke-RunnerTarballEnsure`)

`Infrastructure.Common` retains only genuinely generic utilities. Neither
module depends on the other - the dependency graph stays flat.

Consumer repos install whichever modules they need:

```
PSGallery
  Infrastructure.Common   (SSH, file server, generic utilities)
  Infrastructure.GitHub   (GitHub API, auth, deployments, runner binary)

Infrastructure-E2E
  Install-Module Infrastructure.Common
  Install-Module Infrastructure.GitHub

Infrastructure-GitHubRunners
  Install-Module Infrastructure.Common
  Install-Module Infrastructure.GitHub
```

## Scope

**Infrastructure.GitHub** (new repo + PSGallery package):
- Receives the five GitHub-specific functions moved out of Common.
- Gets its own CI/CD pipeline, versioning, and test suite.
- No `RequiredModules` dependency on Common.

**Infrastructure.Common** (this repo):
- Removes the five GitHub-specific functions.
- Version bumped; consumers that used them update their `Install-Module` calls.

**Consumer repos** (Infrastructure-E2E, Infrastructure-GitHubRunners):
- Add `Install-Module Infrastructure.GitHub` alongside the existing
  `Install-Module Infrastructure.Common`.
- No functional changes - call sites are identical.
