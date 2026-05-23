# Problem: Docker Integration Tests

## Index

- [Summary](#summary)
- [Context](#context)
- [Two CI Patterns](#two-ci-patterns)

---

## Summary

Add tooling for a new category of integration test: tests that run on the
host and connect via SSH to a Docker container acting as the remote machine
under test. Provide reusable CI workflows and manual runner scripts alongside
the existing Docker-hosted pattern.

## Context

Integration tests in this polyrepo family fall into two distinct categories:

1. **Tests that verify PowerShell module behaviour** - these run inside a
   PowerShell Docker container; they do not depend on the host OS. The
   Docker-hosted pattern already exists (`ci-powershell-docker-host.yml`).

2. **Tests that verify SSH-based infrastructure commands** - these must run
   on the host (to access Docker) and connect via SSH to a container that
   acts as the remote machine under test (e.g. Infrastructure-GitHubRunners).
   This is the new pattern introduced by this feature.

The SSH target pattern requires its own reusable workflow, a shared
Dockerfile for the test container, and a manual runner script for local dev.

## Two CI Patterns

### Docker host (`Tests/Integration.DockerHost/`)

Tests run **inside** a Docker container. The runner spins up a fresh
`mcr.microsoft.com/powershell` container per test file, mounts the repo,
and tears it down afterwards.

- Reusable workflow: `ci-powershell-docker-host.yml`
- Consumer wrapper: `ci-docker-host.yml`
- Manual runner: `Run-IntegrationTests-InDocker.ps1`

### Docker target (`Tests/Integration.DockerTarget/`)

Tests run **on the host** and connect via SSH to a container that plays the
role of the remote machine. The Dockerfile for the SSH target image is kept
in Infrastructure-Common and shared across all consumer repos.

- Reusable workflow: `ci-powershell-docker-target.yml`
- Consumer wrapper: `ci-docker-target.yml`
- Manual runner: `Run-IntegrationTests-AgainstDockerTarget.ps1`

See [plan.md](plan.md) for implementation steps.
