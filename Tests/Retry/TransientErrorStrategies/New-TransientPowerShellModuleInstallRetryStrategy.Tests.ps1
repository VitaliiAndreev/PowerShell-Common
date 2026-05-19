BeforeAll {
    # Dot-source the Public file directly so both the exported factory and
    # the file-private Test-TransientPowerShellModuleInstallException land in test scope.
    . "$PSScriptRoot\..\..\..\Infrastructure.Common\Public\Retry\TransientErrorStrategies\New-TransientPowerShellModuleInstallRetryStrategy.ps1"

    # Hand-rolled ErrorRecord factory. ErrorDetails can carry the operator-
    # facing message that PowerShellGet sometimes uses instead of populating
    # Exception.Message; the predicate consults both, so tests need to
    # exercise both shapes.
    function New-TestErrorRecord {
        param(
            [Exception] $Exception,
            [string]    $ErrorDetailsMessage
        )
        $rec = [System.Management.Automation.ErrorRecord]::new(
            $Exception, 'TestError', 'NotSpecified', $null)
        if ($ErrorDetailsMessage) {
            $rec.ErrorDetails =
                [System.Management.Automation.ErrorDetails]::new(
                    $ErrorDetailsMessage)
        }
        return $rec
    }
}

Describe 'New-TransientPowerShellModuleInstallRetryStrategy' {

    It 'returns a hashtable with Name and ShouldRetry keys' {
        $strategy = New-TransientPowerShellModuleInstallRetryStrategy

        $strategy             | Should -BeOfType [hashtable]
        $strategy.Keys        | Should -Contain 'Name'
        $strategy.Keys        | Should -Contain 'ShouldRetry'
        $strategy.ShouldRetry | Should -BeOfType [scriptblock]
    }

    It 'sets Name to TransientPowerShellModuleInstall' {
        (New-TransientPowerShellModuleInstallRetryStrategy).Name |
            Should -Be 'TransientPowerShellModuleInstall'
    }
}

Describe 'New-TransientPowerShellModuleInstallRetryStrategy ShouldRetry predicate' {

    BeforeAll {
        $script:predicate =
            (New-TransientPowerShellModuleInstallRetryStrategy).ShouldRetry
    }

    # --------------------------------------------------------------
    Context 'PSGallery source-resolution failures (must retry)' {
    # --------------------------------------------------------------
        # Scope is now PSGallery-specific only. Generic network failures
        # (DNS, timeout, 5xx) live in TransientNetwork's message-based
        # fallback; consumers that face the wrapped-exception problem
        # OR-compose both strategies.

        It 'returns true for the canonical "Unable to resolve package source" message' {
            # The flake mode the user reported - the source-resolution
            # warning text promoted into the error by the call site so
            # the strategy can see it.
            $ex  = [Exception]::new(
                "No match was found for the specified search criteria and " +
                "module name 'Infrastructure.Common'. " +
                "(caused by: Unable to resolve package source " +
                "'https://www.powershellgallery.com/api/v2'.)")
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeTrue
        }

        It 'returns true when the transient signal lives only in ErrorDetails' {
            # PowerShellGet sometimes uses ErrorDetails for the operator-
            # facing message while Exception.Message stays generic.
            $ex  = [Exception]::new('generic wrapper')
            $rec = New-TestErrorRecord -Exception $ex `
                       -ErrorDetailsMessage `
                           'Unable to resolve package source https://...'

            & $script:predicate $rec | Should -BeTrue
        }

        It 'returns true for "package source ... is unavailable" wording variant' {
            $ex  = [Exception]::new(
                "Package source 'PSGallery' is unavailable.")
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeTrue
        }
    }

    # --------------------------------------------------------------
    Context 'permanent failures (must NOT retry)' {
    # --------------------------------------------------------------

        It 'returns false for bare "No match was found" (typo case)' {
            # Without the warning-stream promotion this is what a real
            # misspelt module name looks like. Retrying would stall for
            # the full attempt budget before the operator gets the error.
            $ex  = [Exception]::new(
                "No match was found for the specified search criteria " +
                "and module name 'Posh-SHH'. " +
                "Try Get-PSRepository to see all available registered " +
                "module repositories.")
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeFalse
        }

        It 'returns false for a publisher / signature failure' {
            # Authenticode / publisher mismatch is a configuration issue,
            # not transient - it will keep failing until -SkipPublisherCheck
            # or the publisher is trusted.
            $ex  = [Exception]::new(
                'Authenticode issuer of the new module does not match the ' +
                'Authenticode issuer of the previously-installed version.')
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeFalse
        }

        It 'returns false for a generic network failure (delegated to TransientNetwork strategy)' {
            # Out of scope for this strategy - PSGallery patterns only.
            # Consumers needing both should OR-compose with
            # New-TransientNetworkRetryStrategy.
            $ex  = [Exception]::new('The operation has timed out')
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeFalse
        }

        It 'returns false for an arbitrary unrelated exception' {
            $ex  = [System.Management.Automation.RuntimeException]::new('boom')
            $rec = New-TestErrorRecord -Exception $ex

            & $script:predicate $rec | Should -BeFalse
        }
    }
}
