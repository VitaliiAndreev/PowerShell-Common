# Problem - Reusable workflow lint across PS and .NET CI

## Index
- [Context](#context)
- [Scope](#scope)
- [Out of scope](#out-of-scope)
- [Constraints](#constraints)
- [Done criteria](#done-criteria)
- [For laymen](#for-laymen)
- [See also](#see-also)

## Context
GitHub Actions workflow YAML is untyped: a typo in a step ID, a
missing required input, a wrong expression syntax (`${{}}` vs `$()`)
or a reference to an undefined needs-output only surfaces at runtime,
often well after the PR is merged. `actionlint` catches every one of
these statically. It is already present locally
(`~/.local/bin/actionlint.exe`) and proved out against
`DotNet-Common/.github/workflows/ci-dotnet.yml` while landing the
threshold gate step. Nothing in the org runs it automatically yet.

## Scope
- One reusable composite action `lint-workflows` in
  `Infrastructure-Common/.github/actions/` that runs `actionlint`
  against the caller repo's `.github/workflows/`.
- Action works on three runner classes: `windows-latest`,
  `ubuntu-latest`, and the self-hosted Ubuntu VMs provisioned by
  `Infrastructure-Vm-Provisioner`.
- `actionlint` baked into the self-hosted VM image alongside JDK
  (`Install-Actionlint.ps1` under `hyper-v/ubuntu/up/post/`).
- Hosted runners pull the binary per-job from the official GitHub
  releases on cache miss (no third-party install script).
- Wired as a preflight step into every CI-class reusable workflow:
  - `Infrastructure-Common/.github/workflows/ci-powershell.yml`
  - `Infrastructure-Common/.github/workflows/ci-powershell-docker-host.yml`
  - `Infrastructure-Common/.github/workflows/ci-powershell-docker-target.yml`
  - `DotNet-Common/.github/workflows/ci-dotnet.yml`

## Out of scope
- Non-CI reusable workflows (`publish.yml`, `release.yml`, `tag.yml`).
  These run on tag/release events where failing on a lint regression
  has more downside than upside; revisit separately.
- Linting consumer repos' workflows. Most consumers' CI is just a
  thin wrapper that calls one of the reusable workflows above, so
  lint coverage of the reusable workflows transitively covers the
  wrapper's `uses:` call surface. Consumers can opt in by calling
  the new action directly.
- Linting composite action `action.yml` files. `actionlint`'s primary
  schema is workflow files; action-file validation is partial and not
  worth the extra surface in this round.
- Pinning `actionlint` by SHA in the per-job download path. The
  release-page download with version-pinning is sufficient
  given the supply-chain posture for hosted runners; the self-hosted
  path is image-baked and not affected.

## Constraints
- **Runner heterogeneity:** PS CI uses GitHub-hosted runners
  (Windows + Ubuntu). .NET CI uses self-hosted Ubuntu VMs. The
  action must work on all three without per-workflow branching.
- **Existing tool-provisioning pattern:** baked-into-image tools live
  under `Infrastructure-Vm-Provisioner/hyper-v/ubuntu/up/post/` (see
  `Install-Jdk.ps1`). New tools follow the same shape - a script
  invoked by `Invoke-VmPostProvisioning.ps1` with corresponding
  uninstall and tests.
- **Two consumption shapes already in use:** DotNet-Common workflows
  invoke composite actions via `uses: ./.github/actions/<name>` (with
  a duplicated `uses: <org>/<repo>/.github/actions/<name>@<ref>`
  fallback for consumer-checkout context). Infrastructure-Common
  workflows instead do an explicit `actions/checkout` of
  Infrastructure-Common into `.ci-common/` and call scripts by path.
  This plan keeps each repo's existing shape rather than unifying
  them in the same step.
- **Cross-platform action body:** PowerShell 7 is on every runner
  class in scope, so the action is `shell: pwsh`. Binary download
  selects by `$IsWindows`/`$IsLinux`.
- **Deterministic version:** the action pins one `actionlint` version
  in a single place (the action's own variable). Bumping that
  variable is the only knob.

## Done criteria
- `lint-workflows` action exists in Infrastructure-Common, with tests
  that validate both the PATH-hit and download paths against a
  fixture workflow directory containing a known-bad workflow.
- `Install-Actionlint.ps1` exists under
  `Infrastructure-Vm-Provisioner/hyper-v/ubuntu/up/post/`, wired into
  `Invoke-VmPostProvisioning.ps1`, with Pester tests mirroring
  `Install-Jdk.Tests.ps1`.
- All four target workflows have the preflight step and stay green
  on a real run.
- Each target repo's README documents the new preflight step where
  it documents the workflow itself.
- One tagged release of Infrastructure-Common carries the new action
  so consumers can pin by SHA (the DotNet-Common wiring lands
  pinned to that SHA, not `@master`).

## For laymen
We have GitHub Actions YAML files that automate builds and tests
across many repos. These YAMLs are easy to break in ways that only
fail later, sometimes silently. A free tool called `actionlint`
catches those mistakes immediately. This change makes every CI
pipeline (the PowerShell ones and the .NET one) run that tool as a
first step, so a broken workflow fails fast with a clear error
instead of producing a confusing failure halfway through.

## See also
- [plan.md](plan.md)
- [DotNet-Common ci-dotnet.yml](../../../../../DotNet-Common/.github/workflows/ci-dotnet.yml)
- [Install-Jdk.ps1 pattern](../../../../../Infrastructure-Vm-Provisioner/hyper-v/ubuntu/up/post/Install-Jdk.ps1)
