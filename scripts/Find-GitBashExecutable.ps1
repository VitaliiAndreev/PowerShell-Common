<#
.SYNOPSIS
    Resolves the path to Git Bash's bash.exe on Windows.

.DESCRIPTION
    Prefers the bash shipped with Git for Windows, derived from git.exe's
    install location (<git-install>\bin\bash.exe). Falling back to PATH
    naively does not work: on Windows 10/11, C:\Windows\System32\bash.exe
    is the WSL launcher and is typically earlier on PATH than Git Bash,
    so a plain Get-Command bash.exe silently picks it up and any
    POSIX-shell script handed to it fails inside WSL.

    Resolution order:
      1. Derive <git-install>\bin\bash.exe from git.exe and return it
         if it exists. This is the reliable path - if Git for Windows
         is installed, its bash is what we want.
      2. Fall back to bash.exe on PATH only if it is NOT the WSL
         launcher under %SystemRoot%. Covers portable Git installs that
         add bash to PATH without git.exe, or third-party bash builds.
      3. Throw with a Git-for-Windows install hint.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-GitBashExecutable {
    # 1. Git for Windows' bash, derived from git.exe's location.
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        # git.exe lives at <git-install>\cmd\git.exe; bash is at
        # <git-install>\bin\bash.exe.
        $candidate = Join-Path `
            (Split-Path -Parent (Split-Path -Parent $git.Source)) 'bin\bash.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    # 2. PATH fallback, but reject the WSL launcher under %SystemRoot%.
    # On Windows 10/11 that path is C:\Windows\System32\bash.exe and it
    # forwards to a WSL distro, which is not what our .sh scripts target.
    $onPath = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($onPath -and -not ($onPath.Source -like "$env:SystemRoot\*")) {
        return $onPath.Source
    }

    throw (
        'Could not find a Git Bash (looked for git.exe-derived ' +
        '<git-install>\bin\bash.exe and a non-WSL bash.exe on PATH). ' +
        'Install Git for Windows.'
    )
}
