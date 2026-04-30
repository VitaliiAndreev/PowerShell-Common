# ---------------------------------------------------------------------------
# Set-DeploymentStatus
#   Posts a status update to an existing GitHub deployment. Wraps
#   POST /repos/{owner}/{repo}/deployments/{id}/statuses.
#
#   Valid states (GitHub API): error, failure, inactive, in_progress,
#   queued, pending, success.
#
#   The polling agent calls this with 'in_progress' when it picks up a
#   deployment and with 'success' or 'failure' when the tests finish.
# ---------------------------------------------------------------------------

function Set-DeploymentStatus {
    [CmdletBinding()]
    param(
        # Bearer token (PAT or GitHub App installation token).
        [Parameter(Mandatory)]
        [string] $Token,

        # GitHub organisation or user that owns the repo.
        [Parameter(Mandatory)]
        [string] $Owner,

        # Repository name (without the owner prefix).
        [Parameter(Mandatory)]
        [string] $Repo,

        # Numeric deployment ID, as returned by Get-PendingDeployment.
        # GitHub deployment IDs exceed Int32.MaxValue - must be [long].
        [Parameter(Mandatory)]
        [long] $DeploymentId,

        # Deployment state string. GitHub accepts: error, failure,
        # inactive, in_progress, queued, pending, success.
        [Parameter(Mandatory)]
        [string] $State,

        # Human-readable description shown in the GitHub UI. Optional
        # but strongly recommended so failures are self-explanatory.
        [Parameter()]
        [string] $Description,

        # URL to job logs. Optional; shown as a link in the GitHub UI.
        [Parameter()]
        [string] $LogUrl
    )

    $body = @{ state = $State }
    if ($PSBoundParameters.ContainsKey('Description')) { $body['description'] = $Description }
    if ($PSBoundParameters.ContainsKey('LogUrl'))      { $body['log_url']     = $LogUrl }

    Invoke-GitHubApi `
        -Token    $Token `
        -Endpoint "repos/$Owner/$Repo/deployments/$DeploymentId/statuses" `
        -Method   'Post' `
        -Body     $body
}
