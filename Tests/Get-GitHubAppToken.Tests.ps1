BeforeAll {
    # Get-GitHubAppToken uses RSA.ImportFromPem, a .NET 5 API not available in
    # Windows PowerShell 5.1. Skip all setup and tests when running under PS 5.
    if ($PSVersionTable.PSVersion.Major -lt 7) { return }

    function Invoke-GitHubApi { param($Token, $Endpoint, $Uri, $Method, $Body) }

    . "$PSScriptRoot\..\Infrastructure.Common\Public\Get-GitHubAppToken.ps1"

    # Generate a 2048-bit RSA key pair. The private key is written to a temp
    # PEM file so the function under test can load it via PrivateKeyPath.
    # The public key stays in $Script:TestRsa for signature verification.
    $Script:TestRsa = [Security.Cryptography.RSA]::Create(2048)
    $Script:KeyPath = [IO.Path]::GetTempFileName() + '.pem'
    # ExportRSAPrivateKeyPem() requires .NET 5+. Build the PEM manually from
    # PKCS#1 DER bytes (ExportRSAPrivateKey is available from .NET Core 3.0).
    $der = $Script:TestRsa.ExportRSAPrivateKey()
    $b64 = [Convert]::ToBase64String($der, [Base64FormattingOptions]::InsertLineBreaks)
    Set-Content -Path $Script:KeyPath -Value "-----BEGIN RSA PRIVATE KEY-----`n$b64`n-----END RSA PRIVATE KEY-----"

    # Decodes a base64url string to raw bytes (reverses the RFC 7515 encoding
    # applied by Get-GitHubAppToken).
    function ConvertFrom-Base64Url ([string] $encoded) {
        $padded = $encoded -replace '-', '+' -replace '_', '/'
        $rem    = $padded.Length % 4
        if ($rem) { $padded += '=' * (4 - $rem) }
        [Convert]::FromBase64String($padded)
    }
}

AfterAll {
    if ($PSVersionTable.PSVersion.Major -lt 7) { return }
    if ($null -ne $Script:TestRsa) { $Script:TestRsa.Dispose() }
    if (Test-Path $Script:KeyPath)  { Remove-Item $Script:KeyPath }
}

Describe 'Get-GitHubAppToken' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    BeforeAll {
        # Capture the JWT produced by a single call so all JWT structure tests
        # share one token without repeating the key-load and sign operation.
        $script:_capturedJwt = $null
        Mock Invoke-GitHubApi {
            $script:_capturedJwt = $Token
            [PSCustomObject]@{ token = 'access_token'; expires_at = '2099-01-01T00:00:00Z' }
        }

        $Script:CallTimeBefore = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        Get-GitHubAppToken -AppId 12345 -InstallationId 99999 -PrivateKeyPath $Script:KeyPath
        $Script:CallTimeAfter  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

        $parts = $script:_capturedJwt -split '\.'
        $Script:JwtHeader      = [Text.Encoding]::UTF8.GetString(
            (ConvertFrom-Base64Url $parts[0])) | ConvertFrom-Json
        $Script:JwtPayloadRaw  = [Text.Encoding]::UTF8.GetString(
            (ConvertFrom-Base64Url $parts[1]))
        $Script:JwtPayload     = $Script:JwtPayloadRaw | ConvertFrom-Json
        $Script:JwtSigBytes    = ConvertFrom-Base64Url $parts[2]
        $Script:JwtSigInput    = [Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])")
    }

    # ------------------------------------------------------------------
    Context 'JWT header' {
    # ------------------------------------------------------------------

        It 'sets alg to RS256' {
            $Script:JwtHeader.alg | Should -Be 'RS256'
        }

        It 'sets typ to JWT' {
            $Script:JwtHeader.typ | Should -Be 'JWT'
        }
    }

    # ------------------------------------------------------------------
    Context 'JWT payload' {
    # ------------------------------------------------------------------

        It 'sets iss to AppId' {
            $Script:JwtPayload.iss | Should -Be 12345
        }

        It 'serializes iss as a bare integer, not a quoted string' {
            # Should -Be coerces types, so "12345" -eq 12345 is true in PS.
            # This test checks the raw JSON to confirm the value is unquoted,
            # which is what GitHub's JWT parser requires.
            $Script:JwtPayloadRaw | Should -Match '"iss":\d'
            $Script:JwtPayloadRaw | Should -Not -Match '"iss":"'
        }

        It 'sets exp exactly 600 seconds after iat' {
            ($Script:JwtPayload.exp - $Script:JwtPayload.iat) | Should -Be 600
        }

        It 'sets iat within the time window of the call' {
            $Script:JwtPayload.iat | Should -BeGreaterOrEqual $Script:CallTimeBefore
            $Script:JwtPayload.iat | Should -BeLessOrEqual    $Script:CallTimeAfter
        }
    }

    # ------------------------------------------------------------------
    Context 'JWT signature' {
    # ------------------------------------------------------------------

        It 'produces a valid RS256 signature verifiable with the public key' {
            $valid = $Script:TestRsa.VerifyData(
                $Script:JwtSigInput,
                $Script:JwtSigBytes,
                [Security.Cryptography.HashAlgorithmName]::SHA256,
                [Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $valid | Should -BeTrue
        }
    }

    # ------------------------------------------------------------------
    Context 'API call' {
    # ------------------------------------------------------------------

        It 'posts to the installation access tokens endpoint for the given installation' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = 'e' } }

            Get-GitHubAppToken -AppId 1 -InstallationId 99999 -PrivateKeyPath $Script:KeyPath

            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $Endpoint -eq 'app/installations/99999/access_tokens' -and
                $Method   -eq 'Post' -and
                $Token    -like '*.*.*'
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'scoped token - Repositories and Permissions' {
    # ------------------------------------------------------------------

        It 'passes Repositories in the request body when specified' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = 'e' } }

            Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath `
                -Repositories @('my-repo')

            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $Body['repositories'] -contains 'my-repo'
            }
        }

        It 'passes Permissions in the request body when specified' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = 'e' } }

            Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath `
                -Permissions @{ administration = 'write' }

            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $Body['permissions']['administration'] -eq 'write'
            }
        }

        It 'passes both Repositories and Permissions together when both are specified' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = 'e' } }

            Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath `
                -Repositories @('repo-a') `
                -Permissions  @{ administration = 'write' }

            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $Body['repositories'] -contains 'repo-a' -and
                $Body['permissions']['administration'] -eq 'write'
            }
        }

        It 'omits Body when neither Repositories nor Permissions is specified' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = 'e' } }

            Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath

            Should -Invoke Invoke-GitHubApi -Times 1 -ParameterFilter {
                $null -eq $Body
            }
        }
    }

    # ------------------------------------------------------------------
    Context 'return value' {
    # ------------------------------------------------------------------

        It 'returns Token from the API response' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 'real_token'; expires_at = 'e' } }

            $result = Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath

            $result.Token | Should -Be 'real_token'
        }

        It 'returns ExpiresAt from the API response' {
            Mock Invoke-GitHubApi { [PSCustomObject]@{ token = 't'; expires_at = '2099-06-15T10:00:00Z' } }

            $result = Get-GitHubAppToken -AppId 1 -InstallationId 2 -PrivateKeyPath $Script:KeyPath

            $result.ExpiresAt | Should -Be '2099-06-15T10:00:00Z'
        }
    }
}
