<#
.SYNOPSIS
    Installs PowerShell.Common locally from source for development use.

.DESCRIPTION
    For development and testing of the module itself only.
    Consuming repos install from PSGallery - they do not call this script.

    Idempotent - skips installation if the module is already up to date.

.EXAMPLE
    .\Install.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root is one level up now that this script lives under scripts\.
$repoRoot    = Split-Path -Parent $PSScriptRoot
$moduleSrc   = Join-Path $repoRoot 'PowerShell.Common'
$moduleDst   = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
                   'WindowsPowerShell\Modules\PowerShell.Common'

$srcVersion  = (Import-PowerShellDataFile `
                    (Join-Path $moduleSrc 'PowerShell.Common.psd1')).ModuleVersion
$dstManifest = Join-Path $moduleDst 'PowerShell.Common.psd1'
$dstVersion  = if (Test-Path $dstManifest) {
                   (Import-PowerShellDataFile $dstManifest).ModuleVersion
               } else { $null }

if ($srcVersion -eq $dstVersion) {
    Write-Host "PowerShell.Common v$srcVersion already installed - skipping." `
        -ForegroundColor Green
    return
}

Write-Host "Installing PowerShell.Common v$srcVersion from source ..."
if (Test-Path $moduleDst) { Remove-Item $moduleDst -Recurse -Force }
Copy-Item -Path $moduleSrc -Destination $moduleDst -Recurse
Write-Host "PowerShell.Common v$srcVersion installed." -ForegroundColor Green
