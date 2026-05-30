<#
.SYNOPSIS
    Publishes GitHub Actions version tags (vX.Y.Z + floating vX) for
    this repo's composite actions and reusable workflows.

.DESCRIPTION
    Thin wrapper that delegates to GitHub-Common's publish-version-tags.sh,
    which implements the GitHub Actions versioning convention (immutable
    semver tag + force-moved major tag, both placed on the resolved
    origin/master commit SHA - never the local checkout).

    Decoupled from the module's ModuleVersion on purpose: action /
    workflow releases are tagged here, and the PowerShell.Common .psd1 is
    bumped separately only when there are actual module changes. This
    keeps PSGallery free of versions that contain no PS code change.

    GitHub-Common is located via the sibling assumption (..\GitHub-Common
    relative to this script's parent). Bash is invoked through Git for
    Windows - resolved by deriving <git-install>\bin\bash.exe from git.exe.
    Plain `bash.exe` on PATH is intentionally NOT preferred because on
    Windows 10/11 it usually resolves to C:\Windows\System32\bash.exe,
    which is the WSL launcher, not Git Bash. See Find-GitBashExecutable.

.PARAMETER Version
    The semver tag to publish, e.g. v1.2.3. If omitted, the underlying
    bash script prompts for it.

.EXAMPLE
    .\Publish-VersionTags.ps1 -Version v1.4.0
#>

param(
    [string] $Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Find-GitBashExecutable.ps1')

# Sibling layout: c:\a_Code\PowerShell-Common and c:\a_Code\GitHub-Common.
# Two levels up from scripts\ to reach the shared repos root.
$scriptPath = Join-Path $PSScriptRoot '..\..\GitHub-Common\scripts\publish-version-tags.sh'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Could not find publish-version-tags.sh at '$scriptPath'. " +
          'Expected GitHub-Common as a sibling of PowerShell-Common.'
}
# Resolve so bash sees an absolute, normalised path (forward slashes are
# fine for Git Bash; backslashes also work, but resolving removes the ..).
$scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path

$bash = Find-GitBashExecutable

# Forward to the bash script. Omitting -Version lets the script prompt
# interactively, matching its double-click behaviour.
$bashArgs = @($scriptPath)
if ($Version) { $bashArgs += $Version }

& $bash @bashArgs
if ($LASTEXITCODE -ne 0) {
    throw "publish-version-tags.sh exited with code $LASTEXITCODE."
}
