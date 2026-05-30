BeforeAll {
    . "$PSScriptRoot\..\.github\actions\tag-from-manifest\Invoke-TagFromManifest.ps1"

    # Stub for git - uses $args (not ValueFromRemainingArguments) to avoid
    # PowerShell binding common parameters like -ErrorAction to positional
    # arguments, which would make flags like 'tag' and '-l' ambiguous.
    function git { }
}

Describe 'Invoke-TagFromManifest' {

    BeforeEach {
        Mock Import-PowerShellDataFile {
            [PSCustomObject]@{ ModuleVersion = '1.0.2' }
        }
    }

    Context 'when the tag already exists' {

        BeforeEach {
            # git tag -l <version> returns the tag name when it exists.
            Mock git { '1.0.2' }
        }

        It 'does not create a tag' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            # Verify git was only called once (the -l check) and never
            # called with 'tag' alone (which would create a new tag).
            Should -Invoke git -Times 1 -Exactly `
                -ParameterFilter { $args[0] -eq 'tag' -and $args[1] -eq '-l' }
        }

        It 'does not push' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 0 `
                -ParameterFilter { $args[0] -eq 'push' }
        }
    }

    Context 'when the tag does not exist' {

        BeforeEach {
            # git tag -l <version> returns empty string when tag is absent.
            Mock git { }
        }

        It 'creates the module tag from the manifest version' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 `
                -ParameterFilter { $args[0] -eq 'tag' -and $args[1] -eq '1.0.2' }
        }

        It 'pushes the tag to origin' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke git -Times 1 `
                -ParameterFilter {
                    $args[0] -eq 'push' -and
                    $args[1] -eq 'origin' -and
                    $args[2] -eq '1.0.2'
                }
        }

        It 'reads the version from the provided psd1 path' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            Should -Invoke Import-PowerShellDataFile -Times 1 `
                -ParameterFilter { $Path -eq 'Module\Module.psd1' }
        }

        It 'does not touch any action-stream tags (vX.Y.Z, vX)' {
            Invoke-TagFromManifest -Psd1 'Module\Module.psd1'
            # No 'tag v...' creates, no 'push origin v...', no force pushes.
            Should -Invoke git -Times 0 -ParameterFilter {
                $args[0] -eq 'tag' -and ($args[1] -like 'v*' -or $args[2] -like 'v*')
            }
            Should -Invoke git -Times 0 -ParameterFilter {
                $args[0] -eq 'push' -and $args -contains '--force'
            }
        }
    }
}
