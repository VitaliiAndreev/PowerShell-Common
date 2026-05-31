function Assert-Wsl2Ready {
    <#
    .SYNOPSIS
        Ensures WSL2 is installed and at least one distro is registered.
        Installs WSL2 and throws a Wsl2NotReady error if not ready.

    .DESCRIPTION
        Callers that depend on WSL2 (wsl --mount, wsl -u root, ...) use this
        to gate execution. Behavior:

          1. Detect wsl.exe on PATH.
          2. Detect at least one registered distro via 'wsl --list --quiet'.
             Both are required because wsl -u root -e sh has no distro to
             target otherwise.
          3. If either is missing, run 'wsl --install' and throw an error
             whose message starts with 'Wsl2NotReady: '. The caller is
             expected to catch that prefix and exit cleanly (typically with
             a reboot prompt).

        Why throw rather than exit:
          - Keeps this function unit-testable. An earlier version called
            exit 0 directly, which terminated the test runner process.

        Why 'wsl --install' is safe to call unconditionally when not ready:
          - On Windows 11 it is idempotent: it enables the
            'Windows Subsystem for Linux' and 'Virtual Machine Platform'
            features if absent, and installs Ubuntu as the default distro.
          - Running as Administrator (already required by callers that
            need wsl --mount) is sufficient; no separate elevation prompt
            is shown.

    .EXAMPLE
        try {
            Assert-Wsl2Ready
            # ... WSL-dependent work ...
        }
        catch {
            if ($_.Exception.Message -match '^Wsl2NotReady: ') {
                Write-Host ($_.Exception.Message -replace '^Wsl2NotReady: ','') `
                    -ForegroundColor Yellow
                exit 0
            }
            throw
        }
    #>
    [CmdletBinding()]
    param()

    $wslExe   = Get-Command 'wsl.exe' -ErrorAction SilentlyContinue
    $wslReady = $false
    if ($null -ne $wslExe) {
        # A distro must exist; wsl -u root -e sh requires one.
        $distroList = wsl --list --quiet 2>&1
        $wslReady   = ($LASTEXITCODE -eq 0) -and ("$distroList" -match '\S')
    }

    if ($wslReady) { return }

    Write-Host "  WSL2 is not ready - installing now ..." -ForegroundColor Cyan
    wsl --install
    Write-Host ""
    throw (
        "Wsl2NotReady: WSL2 has been installed. A reboot may be required " +
        "to complete setup. Please reboot and re-run the operation."
    )
}
