BeforeAll {
    # Dot-source the action script. The InvocationName guard inside
    # skips the side-effecting scan and only loads the helpers.
    $Script:ScriptPath = "$PSScriptRoot\..\.github\actions\lint-no-bare-return-empty-array\Test-NoBareReturnEmptyArray.ps1"
    . $Script:ScriptPath

    # Per-test fixture builder. Drops a tree under $TestDrive with
    # operator-chosen contents and returns the root path.
    function New-LintFixture {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [hashtable] $Files
        )
        $root = Join-Path $TestDrive $Name
        foreach ($rel in $Files.Keys) {
            $full = Join-Path $root $rel
            $dir  = Split-Path $full -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Set-Content -Path $full -Value $Files[$rel] -Encoding UTF8
        }
        return $root
    }
}

Describe 'Find-BareReturnEmptyArrayHits' {

    Context 'detection' {

        It 'flags a bare `return @()` on its own line' {
            $root = New-LintFixture -Name 'bare' -Files @{
                'src\Bad.ps1' = @"
function Foo {
    return @()
}
"@
            }
            $hits = @(Find-BareReturnEmptyArrayHits -SourceRoot $root)
            $hits.Count       | Should -Be 1
            $hits[0].LineNumber | Should -Be 2
        }

        It 'flags multiple occurrences and reports them all' {
            $root = New-LintFixture -Name 'multi' -Files @{
                'A.ps1' = @"
function A { return @() }
function B {
    if (`$x) { 'noop' }
    return @()
}
"@
            }
            # The single-line `return @() }` form does NOT match the
            # anchored pattern (return is not the last token on its
            # line). That is the explicit trade-off documented in the
            # script header; this test pins it.
            $hits = @(Find-BareReturnEmptyArrayHits -SourceRoot $root)
            $hits.Count       | Should -Be 1
            $hits[0].LineNumber | Should -Be 4
        }

        It 'tolerates internal whitespace in @( )' {
            $root = New-LintFixture -Name 'space' -Files @{
                'X.ps1' = @"
function X {
    return @(   )
}
"@
            }
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 1
        }
    }

    Context 'false-positive guards' {

        It 'does NOT flag `return ,@()` (the correct shape)' {
            $root = New-LintFixture -Name 'commaOk' -Files @{
                'Ok.ps1' = @"
function Ok {
    return ,@()
}
"@
            }
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'does NOT flag a comment that mentions `return @()`' {
            $root = New-LintFixture -Name 'commentOnly' -Files @{
                'C.ps1' = @"
function C {
    # Avoid: return @() unrolls to `$null at the caller.
    return ,@()
}
"@
            }
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'does NOT flag `return @(1)` (non-empty array)' {
            $root = New-LintFixture -Name 'nonempty' -Files @{
                'NE.ps1' = @"
function NE {
    return @(1)
}
"@
            }
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 0
        }
    }

    Context 'exclusions' {

        It 'skips files under Tests/' {
            $root = New-LintFixture -Name 'excTests' -Files @{
                'src\Good.ps1' = @"
function G { return ,@() }
"@
                'Tests\Foo.Tests.ps1' = @"
function MockHelper { return @() }
"@
            }
            # Test fixture has a bare return inside Tests/ - excluded.
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'skips files under .ci-common/' {
            $root = New-LintFixture -Name 'excCommon' -Files @{
                'src\Good.ps1' = @"
function G { return ,@() }
"@
                '.ci-common\SomeAction\X.ps1' = @"
function X { return @() }
"@
            }
            (Find-BareReturnEmptyArrayHits -SourceRoot $root).Count | Should -Be 0
        }

        It 'still finds bare returns in non-excluded paths when Tests/ also contains them' {
            $root = New-LintFixture -Name 'mixed' -Files @{
                'src\Bad.ps1' = @"
function B { return @() }
"@
                'Tests\Foo.Tests.ps1' = @"
function M { return @() }
"@
            }
            # src/Bad.ps1 line 1 has the single-line form `return @() }`
            # which does NOT match (anchored pattern). Adjust fixture
            # to a multi-line form so the production hit is real.
            Set-Content -Path (Join-Path $root 'src\Bad.ps1') -Value @"
function B {
    return @()
}
"@ -Encoding UTF8
            $hits = @(Find-BareReturnEmptyArrayHits -SourceRoot $root)
            $hits.Count        | Should -Be 1
            $hits[0].Path      | Should -BeLike '*src*Bad.ps1'
        }
    }

    Context 'return-shape contract' {

        It 'returns an array (not $null) when there are zero hits' {
            $root = New-LintFixture -Name 'empty' -Files @{
                'X.ps1' = "function X { 'noop' }"
            }
            $result = Find-BareReturnEmptyArrayHits -SourceRoot $root
            # Eats its own dogfood: the function must use ,@() so the
            # caller's .Count works on zero matches.
            ($null -eq $result) | Should -BeFalse
            ($result -is [array]) | Should -BeTrue
            $result.Count | Should -Be 0
        }
    }
}
