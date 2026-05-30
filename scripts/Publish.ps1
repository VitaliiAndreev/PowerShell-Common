<#
.SYNOPSIS
    Publishes the PowerShell.Common module to the PowerShell Gallery.

.DESCRIPTION
    Local-only entry point for publishing. CI uses the reusable action
    in .github\actions\publish\ directly - do not call this from workflows.

    Run from the PowerShell-Common repo root after bumping
    ModuleVersion in PowerShell.Common\PowerShell.Common.psd1.
    Requires a PSGallery API key - generate one at:
        https://www.powershellgallery.com/account/apikeys

.PARAMETER ApiKey
    Your PSGallery API key.

.EXAMPLE
    .\Publish.ps1 -ApiKey 'oy2...'
#>

param(
    [Parameter(Mandatory)]
    [string] $ApiKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repo root is one level up now that this script lives under scripts\.
$repoRoot   = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'PowerShell.Common'
$version    = (Import-PowerShellDataFile `
                   (Join-Path $modulePath 'PowerShell.Common.psd1')).ModuleVersion

Write-Host "Publishing PowerShell.Common v$version to PSGallery ..."
$env:API_KEY = $ApiKey
. (Join-Path $repoRoot '.github\actions\publish\Invoke-Publish.ps1')
Invoke-Publish -ModulePath $modulePath
Write-Host "Published. Install with: Install-Module PowerShell.Common" `
    -ForegroundColor Green
