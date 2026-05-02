<#
.NOTES
    Requires PowerShell 7+ (pwsh). RSA.ImportFromPem is a .NET 5+ API
    not available in Windows PowerShell 5.1.
#>

# ---------------------------------------------------------------------------
# Get-GitHubAppToken
#   Generates a short-lived installation access token for a GitHub App.
#
#   Flow:
#     1. Build a JWT (header + payload) signed with the app's RSA private
#        key using RS256 (RSASSA-PKCS1-v1_5 + SHA-256). GitHub requires
#        this algorithm and limits JWT lifetime to 10 minutes.
#     2. Call POST /app/installations/{id}/access_tokens with the JWT as
#        the Bearer token. GitHub validates the JWT and returns a
#        short-lived installation access token (1-hour TTL).
#
#   The returned Token is a bearer token for Invoke-GitHubApi. Callers
#   should refresh it when ExpiresAt is within 5 minutes to avoid
#   mid-operation failures.
#
#   Security: PrivateKeyPath must point to a file secured on disk.
#   The key is loaded into memory only for the duration of the signing
#   operation and disposed immediately after.
# ---------------------------------------------------------------------------

function Get-GitHubAppToken {
    [CmdletBinding()]
    param(
        # App ID shown on the GitHub App's settings page under "App ID".
        # Not the client ID.
        [Parameter(Mandatory)]
        [int] $AppId,

        # Installation ID for the target repository or organisation.
        # Visible on the app's installation page in GitHub settings.
        [Parameter(Mandatory)]
        [int] $InstallationId,

        # Path to the RSA private key (.pem) downloaded from the GitHub App
        # settings page. The file must be readable by the current user.
        [Parameter(Mandatory)]
        [string] $PrivateKeyPath,

        # Restrict the token to these repositories only. When omitted, the
        # token covers all repos in the installation. Use to apply least-
        # privilege: a token scoped to one repo cannot touch others even if
        # the installation has broader access.
        [Parameter()]
        [string[]] $Repositories = @(),

        # Restrict the token to a subset of the installation's declared
        # permissions. Keys are GitHub permission names (e.g. 'administration',
        # 'contents'); values are 'read' or 'write'. When omitted, the token
        # carries all permissions granted to the installation.
        [Parameter()]
        [hashtable] $Permissions = @{}
    )

    # GitHub allows a JWT lifetime of up to 10 minutes (600 seconds).
    # The token is built immediately before the API call so it arrives fresh.
    $now = [DateTimeOffset]::UtcNow
    $iat = $now.ToUnixTimeSeconds()
    $exp = $now.AddMinutes(10).ToUnixTimeSeconds()

    # RFC 7515 base64url: standard base64 with + -> -, / -> _, no padding.
    # Inlined as a scriptblock to avoid polluting the module namespace with a
    # private helper function.
    $toB64Url = {
        param([byte[]] $bytes)
        [Convert]::ToBase64String($bytes) `
            -replace '\+', '-' `
            -replace '/',  '_' `
            -replace '=',  ''
    }

    # Header keys must be in the exact order below to match GitHub's parser
    # expectations (alg before typ). Payload key order is not significant
    # for JWT purposes but is kept consistent for readability.
    $headerB64  = & $toB64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"RS256","typ":"JWT"}'))
    $payloadB64 = & $toB64Url ([Text.Encoding]::UTF8.GetBytes(
        "{`"iat`":$iat,`"exp`":$exp,`"iss`":$AppId}"))

    $signingInput = "$headerB64.$payloadB64"

    # Load the private key, sign, then immediately dispose the RSA object so
    # the key material does not linger in memory beyond this scope.
    $rsa = [Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem((Get-Content -Path $PrivateKeyPath -Raw -ErrorAction Stop))
        $sigBytes = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes($signingInput),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    }
    finally {
        $rsa.Dispose()
    }

    $jwt = "$signingInput.$(& $toB64Url $sigBytes)"

    # Build the request body only when scope restrictions are provided.
    # Omitting the body entirely (rather than sending an empty object) matches
    # the GitHub API's documented default behaviour for unscoped tokens.
    $apiParams = @{
        Token    = $jwt
        Endpoint = "app/installations/$InstallationId/access_tokens"
        Method   = 'Post'
    }

    $body = @{}
    if ($Repositories.Count -gt 0) { $body['repositories'] = $Repositories }
    if ($Permissions.Count  -gt 0) { $body['permissions']  = $Permissions  }
    if ($body.Count         -gt 0) { $apiParams['Body']    = $body          }

    $response = Invoke-GitHubApi @apiParams

    [PSCustomObject]@{
        Token     = $response.token
        ExpiresAt = $response.expires_at
    }
}
