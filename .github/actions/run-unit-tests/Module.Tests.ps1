# Shared module registration test, injected by Run-Tests.ps1 for every repo
# in the Infrastructure-* family. The module root is passed via the
# MODULE_TESTS_ROOT environment variable set by Run-Tests.ps1 before Pester
# is invoked.
BeforeAll {
    $root = $env:MODULE_TESTS_ROOT
    if (-not $root) {
        throw 'MODULE_TESTS_ROOT env var is not set. This file must be run via Run-Tests.ps1.'
    }

    $script:manifest    = Import-PowerShellDataFile (
        Get-ChildItem -Path $root -Filter '*.psd1' | Select-Object -First 1 -ExpandProperty FullName)
    $script:psm1Content = Get-Content (
        Get-ChildItem -Path $root -Filter '*.psm1' | Select-Object -First 1 -ExpandProperty FullName) -Raw

    # Convention: filename == function name (e.g. ConvertTo-Array.ps1).
    # Recursive so repos can group related functions into subfolders
    # (e.g. Public\Retry\) without breaking the registration check.
    # Flat Public\ layouts still match - recursion is a superset.
    $script:publicFns = Get-ChildItem `
        -Path    ([IO.Path]::Combine($root, 'Public')) `
        -Filter  '*.ps1' `
        -Recurse |
        Select-Object -ExpandProperty BaseName
}

Describe 'Module registration' {

    It 'all Public functions are listed in FunctionsToExport' {
        $missing = $script:publicFns |
            Where-Object { $_ -notin $script:manifest.FunctionsToExport }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are dot-sourced in the psm1' {
        $missing = $script:publicFns |
            Where-Object { $script:psm1Content -notmatch [regex]::Escape("$_.ps1") }
        $missing | Should -BeNullOrEmpty
    }

    It 'all Public functions are in Export-ModuleMember' {
        $missing = $script:publicFns |
            Where-Object { $script:psm1Content -notmatch [regex]::Escape($_) }
        $missing | Should -BeNullOrEmpty
    }
}
