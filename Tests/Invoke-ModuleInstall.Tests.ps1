BeforeAll {
    # Invoke-ModuleInstall delegates the install to Invoke-WithRetry,
    # classifies failures with New-TransientPowerShellModuleInstallRetryStrategy,
    # and uses New-ExponentialBackoffStrategy for the backoff curve.
    # Dot-source all four so the install path runs end-to-end - retry +
    # classification are part of the function's contract now, not a
    # black box.
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Retry\Invoke-WithRetry.ps1"
    . "$PSScriptRoot\..\Infrastructure.Common\Private\Retry\Assert-RetryStrategyShape.ps1"
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Retry\BackoffStrategies\New-ExponentialBackoffStrategy.ps1"
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientPowerShellModuleInstallRetryStrategy.ps1"
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientNetworkRetryStrategy.ps1"
    . "$PSScriptRoot\..\Infrastructure.Common\Public\Invoke-ModuleInstall.ps1"

    # Canonical transient error messages used by retry-behaviour tests.
    # Pulled into constants so each test does not redeclare the string
    # and so a future PowerShellGet wording change has one spot to update.
    $script:TransientErrorMessage =
        'Unable to resolve package source ' +
        'https://www.powershellgallery.com/api/v2'
    $script:PermanentErrorMessage =
        "No match was found for the specified search criteria and " +
        "module name 'Posh-SHH'. " +
        "Try Get-PSRepository to see all available registered module repositories."
}

Describe 'Invoke-ModuleInstall' {

    BeforeEach {
        Mock Install-Module {}
        Mock Import-Module  {}
        # Default: nothing loaded in the session. Contexts that need to
        # simulate a previously-loaded version override this filter.
        Mock Get-Module {} -ParameterFilter { -not $ListAvailable }
        Mock Remove-Module {}
        # Suppress real sleeps in the retry loop so failure-path tests
        # do not pay 10+ seconds of wall-clock per retried attempt.
        Mock Start-Sleep {}
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

    Context 'install-time retry on transient PSGallery failures' {
    # ------------------------------------------------------------------
        # The flake mode this protects against: PSGallery returns
        # "Unable to resolve package source" intermittently. Without
        # retry the provision run dies even though a retry seconds
        # later would have succeeded. ErrorAction=Stop on Install-Module
        # is what lets the retry loop's catch see the failure at all.

        BeforeEach {
            Mock Get-Module {} -ParameterFilter { $ListAvailable }
        }

        It 'passes -ErrorAction Stop to Install-Module so failures are terminating' {
            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            Should -Invoke Install-Module -Times 1 -Exactly -ParameterFilter {
                $ErrorAction -eq 'Stop'
            }
        }

        It 'actually promotes non-terminating Install-Module errors (behavioural check)' {
            # The previous test only proves the parameter is set; this
            # test proves the consequence holds. The mock uses Write-Error
            # (non-terminating by default). If -ErrorAction Stop were not
            # bound on the call, the catch in Invoke-ModuleInstall would
            # never see the failure - the install would silently no-op
            # and the function would fall through to whatever version is
            # cached, defeating the whole point of the retry. So if this
            # test stops asserting two invocations, it means the -ErrorAction
            # Stop plumbing has regressed even if the surface assertion
            # above still passes.
            $script:_attempt = 0
            $msg = $script:TransientErrorMessage
            Mock Install-Module {
                $script:_attempt++
                if ($script:_attempt -lt 2) {
                    # Write-Error: non-terminating unless the caller bound
                    # -ErrorAction Stop, in which case PowerShell promotes
                    # it to terminating before returning to the catch.
                    Write-Error $msg
                }
            }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } | Should -Not -Throw

            # Two calls = first was promoted-and-caught-and-retried,
            # second succeeded.
            Should -Invoke Install-Module -Times 2 -Exactly
        }

        It 'retries Install-Module on transient failure and succeeds when a later attempt works' {
            # Two failures then a success - the function must call
            # Install-Module three times total and not throw.
            $script:_installAttempt = 0
            $msg = $script:TransientErrorMessage
            Mock Install-Module {
                $script:_installAttempt++
                if ($script:_installAttempt -lt 3) {
                    throw $msg
                }
            }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } | Should -Not -Throw

            Should -Invoke Install-Module -Times 3 -Exactly
        }

        It 'gives up and rethrows after the configured attempt budget on persistent transient failures' {
            # Retry policy is internal to Invoke-ModuleInstall - no knob
            # to tighten the budget from the test. Start-Sleep is mocked
            # so the test runs in milliseconds regardless of attempt
            # count.
            $msg = $script:TransientErrorMessage
            Mock Install-Module { throw $msg }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } |
                Should -Throw -ExpectedMessage '*resolve package source*'

            # Internal default: 6 attempts.
            Should -Invoke Install-Module -Times 6 -Exactly
        }

        It 'does NOT retry permanent failures (e.g. typo / module-not-found with no source-resolution warning)' {
            # The transient-install strategy classifies "No match was
            # found" alone as permanent so a misspelt module name fails
            # fast instead of stalling the full retry budget. This is
            # the corollary of the classifier being narrow on purpose.
            $msg = $script:PermanentErrorMessage
            Mock Install-Module { throw $msg }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } |
                Should -Throw -ExpectedMessage '*No match was found*'

            Should -Invoke Install-Module -Times 1 -Exactly
            Should -Invoke Start-Sleep    -Times 0
        }

        It 'classifies a "No match was found" error as transient when a source-resolution warning preceded it' {
            # Real-world flake shape: PSGallery resolution fails as a
            # WARNING; downstream terminating error is the ambiguous
            # "No match was found". Invoke-ModuleInstall captures the
            # warning stream and promotes the source-resolution message
            # into the error text so the strategy can still classify
            # the case as transient.
            $script:_attempt   = 0
            $warning  = ('Unable to resolve package source ' +
                         'https://www.powershellgallery.com/api/v2')
            $errorMsg = $script:PermanentErrorMessage
            Mock Install-Module {
                $script:_attempt++
                Write-Warning $warning
                if ($script:_attempt -lt 2) { throw $errorMsg }
            }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } | Should -Not -Throw

            # Two calls = first failed and was classified transient,
            # second succeeded.
            Should -Invoke Install-Module -Times 2 -Exactly
        }

        It 'uses exponential backoff between retries' {
            # Internal defaults: 6 attempts, base 10 s, cap 300 s. Delays
            # between attempts: 10, 20, 40, 80, 160 (cap not hit at this
            # depth). No sleep after the final failing attempt.
            $msg = $script:TransientErrorMessage
            Mock Install-Module { throw $msg }

            { Invoke-ModuleInstall -ModuleName 'Foo' `
                  -MinimumVersion '1.0.0' } |
                Should -Throw

            foreach ($expected in @(10, 20, 40, 80, 160)) {
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter {
                    $Seconds -eq $expected
                }
            }
            # Total sleeps = attempts - 1; no sleep after the last
            # failing attempt (would just delay the throw).
            Should -Invoke Start-Sleep -Times 5 -Exactly
        }

        It 'does not call Install-Module (or retry) when the module is already at the minimum version' {
            Mock Get-Module {
                [PSCustomObject]@{ Name = 'Foo'; Version = [Version]'1.0.0' }
            } -ParameterFilter { $ListAvailable }

            Invoke-ModuleInstall -ModuleName 'Foo' -MinimumVersion '1.0.0'

            Should -Invoke Install-Module -Times 0
            Should -Invoke Start-Sleep    -Times 0
        }
    }
}
