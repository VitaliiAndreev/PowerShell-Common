function Invoke-TagFromManifest {
    # Reads the ModuleVersion from the given .psd1 manifest and creates a
    # matching git tag, then pushes it to origin. If the tag already exists
    # (e.g. the psd1 was touched without a version bump, or the workflow
    # re-ran), the step is skipped silently.
    #
    # Pushing the tag triggers the publish workflow, which runs tests and
    # publishes the module to PSGallery.
    #
    # Scope: this action manages the MODULE tag stream only (bare X.Y.Z).
    # The GitHub Actions consumer tag stream (vX.Y.Z + rolling vX) is fully
    # decoupled and lives in the manual Publish-VersionTags.ps1 path - the
    # two namespaces never collide (X.Y.Z vs vX.Y.Z are different names),
    # so each stream can advance on its own cadence without coordinating.
    param(
        [Parameter(Mandatory)]
        [string] $Psd1
    )

    $version = (Import-PowerShellDataFile $Psd1).ModuleVersion

    # git tag -l returns the tag name if it exists, empty string otherwise.
    if (git tag -l $version) {
        Write-Host "Tag '$version' already exists - nothing to do."
        # Signal to the calling workflow that no new tag was created so the
        # publish job can be skipped. Without this, publish runs on every psd1
        # touch (e.g. comment edits) and fails trying to re-publish an existing
        # version to PSGallery.
        "tag_created=false" >> $env:GITHUB_OUTPUT
        return
    }

    git tag $version
    git push origin $version
    Write-Host "Created and pushed tag '$version'."
    "tag_created=true" >> $env:GITHUB_OUTPUT
}
