<#
.SYNOPSIS
    Fails the build if any production .ps1 under -SourceRoot contains a
    bare `return @()` statement.

.DESCRIPTION
    Canonical lint for the Infrastructure-* polyrepo family. Called by
    the reusable ci-powershell.yml workflow before the unit tests run.

    A bare `return @()` unrolls the empty array on the output stream so
    the caller sees $null instead of an empty array - the producer-side
    dual of the single-match `.Count` scalar trap. Use `return ,@()` to
    preserve array shape across the function boundary. See
    Infrastructure-Common's memory entry
    `feedback_powershell_return_empty_array.md` for the failure that
    motivated this lint (JdkProvider.Get-DesiredVersions silently
    skipping the JDK uninstall path).

    The regex `^\s*return\s+@\(\s*\)\s*$` is anchored at line start
    (after whitespace) and end so comments that mention the literal
    text `return @()` are not false-positives. The codebase convention
    puts return on its own line, so this is precise enough without an
    AST walker. Internal whitespace is tolerated.

    Hits are emitted as GitHub Actions error annotations so they show
    as red squiggles in the PR diff view. Local invocation gets the
    same lines printed plain.

.PARAMETER SourceRoot
    Root directory of the repo under lint. Defaults to the current
    location so the script can be run interactively.

.EXAMPLE
    .\Test-NoBareReturnEmptyArray.ps1 -SourceRoot C:\a_Code\Infrastructure-Vm-Provisioner

.NOTES
    The executable body is guarded by an InvocationName check so the
    file can be dot-sourced from tests to expose the helper functions
    without firing the side-effecting scan. Mirrors the convention
    used by Run-IntegrationTests.ps1.
#>

param(
    [string] $SourceRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Regex documented in the file header. Defined here (script scope) so
# both the function and any future helpers see exactly the same shape;
# bare-string duplication would invite drift.
$script:BareReturnEmptyArrayPattern = '^\s*return\s+@\(\s*\)\s*$'

# Path patterns that must never be linted. .ci-common is the sibling
# checkout of Infrastructure-Common created by ci-powershell.yml;
# excluded so the lint applies only to the caller repo's own
# production code. Tests/ is excluded because fixtures and mock
# helpers legitimately construct empty arrays in places that look
# like returns.
$script:DefaultLintExcludePatterns = @(
    '^\.ci-common([\\/]|$)',
    '(^|[\\/])Tests([\\/]|$)'
)

function Find-BareReturnEmptyArrayHits {
    <#
    .SYNOPSIS
        Returns hit records (Path, LineNumber, Line) for every bare
        `return @()` in production .ps1 under -SourceRoot.

    .DESCRIPTION
        Pure: no Write-Host, no exit. Lets tests assert on the result
        without parsing stdout. The script body below emits and exits;
        this function does neither.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $SourceRoot,

        [string[]] $ExcludePatterns = $script:DefaultLintExcludePatterns
    )

    $root = (Resolve-Path -LiteralPath $SourceRoot).Path

    $files = Get-ChildItem -Path $root -Recurse -File -Filter '*.ps1' |
        Where-Object {
            $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
            foreach ($p in $ExcludePatterns) {
                if ($rel -match $p) { return $false }
            }
            $true
        }

    # Comma-operator wrap so a single hit (or zero hits) round-trips as
    # an array; otherwise the caller's @().Count would scalar-throw.
    # Eats its own dogfood.
    return ,@($files | Select-String -Pattern $script:BareReturnEmptyArrayPattern)
}

# Dot-source guard: when invoked as `. .\Test-NoBareReturnEmptyArray.ps1`
# (from tests) the executable body is skipped so the helpers above are
# exposed without firing the scan. Mirrors Run-IntegrationTests.ps1.
if ($MyInvocation.InvocationName -ne '.') {

    $hits = Find-BareReturnEmptyArrayHits -SourceRoot $SourceRoot

    if (@($hits).Count -eq 0) {
        # Files-scanned count for the OK line is computed here (not in
        # the function) because the function's contract is "return
        # hits", not "report progress".
        $root      = (Resolve-Path -LiteralPath $SourceRoot).Path
        $fileCount = (Get-ChildItem -Path $root -Recurse -File -Filter '*.ps1' |
            Where-Object {
                $rel = $_.FullName.Substring($root.Length).TrimStart('\','/')
                foreach ($p in $script:DefaultLintExcludePatterns) {
                    if ($rel -match $p) { return $false }
                }
                $true
            }).Count
        Write-Host "Lint OK: no bare 'return @()' in production .ps1 (files scanned: $fileCount)."
        exit 0
    }

    foreach ($h in $hits) {
        Write-Host (
            "::error file=$($h.Path),line=$($h.LineNumber)::" +
            "Bare 'return @()' unrolls to `$null at the caller. " +
            "Use 'return ,@()' to preserve array shape."
        )
    }
    Write-Host "Lint FAILED: $(@($hits).Count) bare 'return @()' occurrence(s) found."
    exit 1
}
