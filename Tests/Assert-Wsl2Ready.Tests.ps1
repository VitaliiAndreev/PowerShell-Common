BeforeAll {
    # wsl stub - uses $args to avoid parameter-binding conflicts with the
    # --list / --install flags passed by the function.
    function wsl { $global:LASTEXITCODE = 0 }

    . "$PSScriptRoot\..\PowerShell.Common\Public\Assert-Wsl2Ready.ps1"
}

Describe 'Assert-Wsl2Ready' {

    Context 'WSL2 is ready' {

        It 'returns without throwing when wsl.exe is on PATH and a distro exists' {
            Mock Get-Command { [PSCustomObject]@{ Name = 'wsl.exe' } } `
                -ParameterFilter { $Name -eq 'wsl.exe' }
            # wsl --list --quiet returns at least one non-whitespace token.
            Mock wsl { $global:LASTEXITCODE = 0; return 'Ubuntu' }

            { Assert-Wsl2Ready } | Should -Not -Throw
        }

        It 'does not call wsl --install when ready' {
            Mock Get-Command { [PSCustomObject]@{ Name = 'wsl.exe' } } `
                -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock wsl { $global:LASTEXITCODE = 0; return 'Ubuntu' }

            Assert-Wsl2Ready

            Should -Invoke wsl -Times 0 `
                -ParameterFilter { $args -contains '--install' }
        }
    }

    Context 'WSL2 is not ready' {
    # ------------------------------------------------------------------
    # When wsl.exe is absent or no distro is registered, the function
    # runs wsl --install and throws a Wsl2NotReady error. Callers catch
    # that prefix and exit cleanly (typically with a reboot prompt).
    #
    # The path was deliberately implemented as a throw rather than
    # exit 0 to keep the function unit-testable - exit would terminate
    # the test runner process.

        It 'throws a Wsl2NotReady error when wsl.exe is not found' {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'wsl.exe' }

            { Assert-Wsl2Ready } |
                Should -Throw -ExpectedMessage 'Wsl2NotReady:*'
        }

        It 'throws a Wsl2NotReady error when no WSL2 distro is registered' {
            Mock Get-Command { [PSCustomObject]@{ Name = 'wsl.exe' } } `
                -ParameterFilter { $Name -eq 'wsl.exe' }
            # wsl --list returns exit code 0 but empty output - no distro.
            Mock wsl { $global:LASTEXITCODE = 0; return '' }

            { Assert-Wsl2Ready } |
                Should -Throw -ExpectedMessage 'Wsl2NotReady:*'
        }

        It 'calls wsl --install before throwing when WSL2 is not ready' {
            Mock Get-Command { } -ParameterFilter { $Name -eq 'wsl.exe' }
            Mock wsl {}

            { Assert-Wsl2Ready } | Should -Throw

            # wsl --install should have been called to initiate setup.
            Should -Invoke wsl `
                -ParameterFilter { $args -contains '--install' }
        }
    }
}
