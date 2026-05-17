BeforeAll {
    # Invoke-ModuleInstall has no external dependencies so it can be
    # dot-sourced directly with no stubs required.
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Invoke-ModuleInstall.ps1"
}

Describe 'Invoke-ModuleInstall' {

    BeforeEach {
        Mock Install-Module {}
        Mock Import-Module  {}
        # Default: nothing loaded in the session. Contexts that need to
        # simulate a previously-loaded version override this filter.
        Mock Get-Module {} -ParameterFilter { -not $ListAvailable }
        Mock Remove-Module {}
    }

    Context 'module not installed' {

        BeforeEach {
            Mock Get-Module {} -ParameterFilter { $ListAvailable }
        }

        It 'calls Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }

        It 'passes the correct module name to Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Foo'
            }
        }

        It 'passes AllowClobber to Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $AllowClobber -eq $true
            }
        }

        It 'forwards MinimumVersion to Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $MinimumVersion -eq [Version]'1.0.0'
            }
        }
    }

    Context 'module installed below minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.9.0' }
            } -ParameterFilter { $ListAvailable }
        }

        It 'calls Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'module installed at exactly the minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }
        }

        It 'does not call Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'module installed above minimum version' {

        BeforeEach {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'2.5.0' }
            } -ParameterFilter { $ListAvailable }
        }

        It 'does not call Install-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }

        It 'calls Import-Module' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'no MinimumVersion specified' {

        It 'installs when the module is absent' {
            Mock Get-Module {} -ParameterFilter { $ListAvailable }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Install-Module -Times 1 -Exactly
        }

        It 'does not pass MinimumVersion to Install-Module when omitted' {
            Mock Get-Module {} -ParameterFilter { $ListAvailable }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $null -eq $MinimumVersion
            }
        }

        It 'does not install when the module is already present' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.1.0' }
            } -ParameterFilter { $ListAvailable }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Install-Module -Times 0
        }

        It 'always imports the module' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.1.0' }
            } -ParameterFilter { $ListAvailable }
            Invoke-ModuleInstall -ModuleName 'Foo'
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }

    Context 'multiple versions installed' {

        It 'uses the highest installed version for comparison' {
            # Simulates having both 0.8.0 and 1.1.0 installed.
            # Sort-Object Version -Descending picks 1.1.0, which meets the
            # minimum, so Install-Module must not be called.
            Mock Get-Module {
                @(
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.8.0' },
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.1.0' }
                )
            } -ParameterFilter { $ListAvailable }
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'
            Should -Invoke Install-Module -Times 0
        }
    }

    Context 'older version already loaded in the session' {
        # Guards against the two-versions-live trap: when a previous
        # session run imported an old version and Invoke-ModuleInstall
        # then installs a newer one, both end up loaded simultaneously
        # and command resolution becomes order-dependent. The function
        # must unload any loaded versions before re-importing.

        It 'removes any loaded versions before importing' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.9.0' }
            } -ParameterFilter { -not $ListAvailable }

            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            Should -Invoke Remove-Module -Times 1 -Exactly
            Should -Invoke Import-Module -Times 1 -Exactly
        }

        It 'does not call Remove-Module when no version is loaded' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }
            # Default BeforeEach mock returns nothing for the loaded check.

            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            Should -Invoke Remove-Module -Times 0
        }

        It 'skips unload and reimport when target version is already the only loaded one' {
            # Avoids wasted reload work for script modules. Reload only
            # happens when there is a real mismatch (multiple versions
            # loaded, or loaded version differs from highest available).
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { -not $ListAvailable }

            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            Should -Invoke Remove-Module -Times 0
            Should -Invoke Import-Module -Times 0
        }

        It 'reloads when multiple versions are loaded even if one matches the target' {
            # Two-versions-live trap: command resolution is order-
            # dependent, so even a "matching" version among them is not
            # safe. Unload everything and reimport.
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }
            Mock Get-Module {
                @(
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' },
                    [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'0.9.0' }
                )
            } -ParameterFilter { -not $ListAvailable }

            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            # Pester counts one Remove-Module invocation per pipeline item.
            Should -Invoke Remove-Module -Times 2 -Exactly
            Should -Invoke Import-Module -Times 1 -Exactly
        }
    }
}
