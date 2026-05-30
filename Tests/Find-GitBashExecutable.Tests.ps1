BeforeAll {
    . "$PSScriptRoot\..\scripts\Find-GitBashExecutable.ps1"

    # %SystemRoot% is what the function checks the PATH fallback against
    # to reject WSL's bash launcher. Pin it for the WSL-rejection test.
    $script:SystemRoot = $env:SystemRoot
}

Describe 'Find-GitBashExecutable' {

    BeforeEach {
        # Unfiltered catch-alls so calls that don't match the specific
        # filters below remain visible to Should -Invoke. See memory note
        # feedback_pester5_mock_fallthrough.
        Mock Get-Command { }
        Mock Test-Path { }
    }

    Context 'git.exe is on PATH and bash exists alongside it' {

        BeforeEach {
            Mock Get-Command -ParameterFilter { $Name -eq 'git.exe' } {
                [pscustomobject]@{ Source = 'C:\Program Files\Git\cmd\git.exe' }
            }
            Mock Test-Path -ParameterFilter {
                $LiteralPath -eq 'C:\Program Files\Git\bin\bash.exe'
            } { $true }
        }

        It 'returns the derived bash.exe under the Git install bin dir' {
            Find-GitBashExecutable | Should -Be 'C:\Program Files\Git\bin\bash.exe'
        }

        It 'does not consult bash.exe on PATH (short-circuits after deriving)' {
            Find-GitBashExecutable | Out-Null
            Should -Invoke Get-Command -Times 0 `
                -ParameterFilter { $Name -eq 'bash.exe' }
        }
    }

    Context 'git.exe is not on PATH but a non-WSL bash.exe is' {

        BeforeEach {
            Mock Get-Command -ParameterFilter { $Name -eq 'bash.exe' } {
                [pscustomobject]@{ Source = 'C:\Tools\bash.exe' }
            }
        }

        It 'falls back to the non-WSL bash.exe on PATH' {
            Find-GitBashExecutable | Should -Be 'C:\Tools\bash.exe'
        }
    }

    Context 'only the WSL launcher bash.exe is on PATH' {

        BeforeEach {
            # Windows 10/11's C:\Windows\System32\bash.exe forwards to a
            # WSL distro - the function must refuse it.
            Mock Get-Command -ParameterFilter { $Name -eq 'bash.exe' } {
                [pscustomobject]@{ Source = "$script:SystemRoot\System32\bash.exe" }
            }
        }

        It 'rejects the WSL bash and throws the Git-for-Windows hint' {
            { Find-GitBashExecutable } |
                Should -Throw '*Install Git for Windows*'
        }
    }

    Context 'git.exe is on PATH but no bash.exe alongside it, and no non-WSL fallback' {

        BeforeEach {
            Mock Get-Command -ParameterFilter { $Name -eq 'git.exe' } {
                [pscustomobject]@{ Source = 'C:\Program Files\Git\cmd\git.exe' }
            }
            # Test-Path on derived path returns $null/falsy; catch-all
            # Get-Command for bash.exe also returns nothing.
        }

        It 'probes the derived path before falling back' {
            { Find-GitBashExecutable } | Should -Throw
            Should -Invoke Test-Path -Times 1 -Exactly -ParameterFilter {
                $LiteralPath -eq 'C:\Program Files\Git\bin\bash.exe'
            }
        }

        It 'throws the Git-for-Windows hint when no candidate found' {
            { Find-GitBashExecutable } |
                Should -Throw '*Install Git for Windows*'
        }
    }

    Context 'neither git.exe nor bash.exe is on PATH' {

        It 'throws the Git-for-Windows hint' {
            { Find-GitBashExecutable } |
                Should -Throw '*Install Git for Windows*'
        }

        It 'does not probe Test-Path (no candidate path to check)' {
            { Find-GitBashExecutable } | Should -Throw
            Should -Invoke Test-Path -Times 0
        }
    }
}
