BeforeAll {
    function Invoke-GitHubApi { param($Token, $Endpoint, $Uri, $Method, $Body) }

    . "$PSScriptRoot\..\Infrastructure.Common\Public\Set-DeploymentStatus.ps1"
}

Describe 'Set-DeploymentStatus' {

    BeforeAll {
        Mock Invoke-GitHubApi {}
    }

    # ------------------------------------------------------------------
    Context 'URI' {
    # ------------------------------------------------------------------

        It 'calls the correct deployments statuses endpoint' {
            Set-DeploymentStatus `
                -Token 'tok' -Owner 'myorg' -Repo 'myrepo' `
                -DeploymentId 42 -State 'success'

            Should -Invoke Invoke-GitHubApi -ParameterFilter {
                $Endpoint -eq 'repos/myorg/myrepo/deployments/42/statuses'
            }
        }

        It 'accepts a deployment ID larger than Int32.MaxValue' {
            { Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' `
                -DeploymentId 4534787775 -State 'success' } |
                Should -Not -Throw
        }
    }

    # ------------------------------------------------------------------
    Context 'method' {
    # ------------------------------------------------------------------

        It 'uses POST' {
            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 -State 'success'

            Should -Invoke Invoke-GitHubApi -ParameterFilter { $Method -eq 'Post' }
        }
    }

    # ------------------------------------------------------------------
    Context 'request body' {
    # ------------------------------------------------------------------

        It 'includes state in the body' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 -State 'in_progress'

            $script:_body['state'] | Should -Be 'in_progress'
        }

        It 'includes description when provided' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 `
                -State 'failure' -Description 'Tests failed'

            $script:_body['description'] | Should -Be 'Tests failed'
        }

        It 'omits description when not provided' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 -State 'success'

            $script:_body.ContainsKey('description') | Should -BeFalse
        }

        It 'includes log_url when provided' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 `
                -State 'success' -LogUrl 'https://logs.example.com/run/99'

            $script:_body['log_url'] | Should -Be 'https://logs.example.com/run/99'
        }

        It 'omits log_url when not provided' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 -State 'success'

            $script:_body.ContainsKey('log_url') | Should -BeFalse
        }

        It 'includes all optional fields when all are provided' {
            $script:_body = $null
            Mock Invoke-GitHubApi { $script:_body = $Body }

            Set-DeploymentStatus `
                -Token 'tok' -Owner 'o' -Repo 'r' -DeploymentId 1 `
                -State 'error' -Description 'Timed out' -LogUrl 'https://logs.example.com/1'

            $script:_body['state']       | Should -Be 'error'
            $script:_body['description'] | Should -Be 'Timed out'
            $script:_body['log_url']     | Should -Be 'https://logs.example.com/1'
        }
    }

    # ------------------------------------------------------------------
    Context 'token passthrough' {
    # ------------------------------------------------------------------

        It 'passes the token to Invoke-GitHubApi' {
            Set-DeploymentStatus `
                -Token 'secret_bearer' -Owner 'o' -Repo 'r' `
                -DeploymentId 1 -State 'success'

            Should -Invoke Invoke-GitHubApi -ParameterFilter { $Token -eq 'secret_bearer' }
        }
    }
}
