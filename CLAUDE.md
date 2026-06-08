# CLAUDE.md

Guidance for Claude Code working in this repository. This file covers project intent, conventions, and procedural guidance that isn't captured in the agent reference docs:

- [`.claude/instructions.md`](.claude/instructions.md) — tech stack, personality, requirements
- [`.claude/build-commands.md`](.claude/build-commands.md) — local lint / build / inspection commands
- [`.claude/directory-structure.md`](.claude/directory-structure.md) — directory-by-directory roles
- [`.claude/conventions.md`](.claude/conventions.md) — coding conventions for this repo
- [`.claude/git-hooks.md`](.claude/git-hooks.md) — required local git hooks (must be installed per clone)

<!-- Auto-load the reference docs above so Claude has them in context from session start. -->
@.claude/instructions.md
@.claude/build-commands.md
@.claude/directory-structure.md
@.claude/conventions.md
@.claude/git-hooks.md

## What this repository is

`runner-images` builds customized [Actions Runner Controller](https://github.com/actions/actions-runner-controller) (ARC) container images for Hedera's GitHub Actions self-hosted runners, and publishes them to the GitHub Container Registry (`ghcr.io/hashgraph/runner-images`). The repository holds **Dockerfiles plus the GitHub Actions automation that builds, versions, and releases them** — it ships container images, not application code or a daemon.

The actual runner binary is upstream (`actions/runner`); this repo wraps it in an image preloaded with a developer toolchain (git, docker CLI + buildx + compose, gh, jq, yq, skopeo, ansible, task, semver, jfrog CLI, …) and a hosted **tool cache** (Java, Node, Go, Kind, Helm, Terraform) baked in at `/home/runner/_work/_tool`. When in doubt about whether to add something, prefer keeping the image lean and the build reproducible over adding convenience tooling.

**License**: Apache License 2.0. Source files that carry a copyright header use the `Copyright (C) <year> Hedera Hashgraph, LLC` Apache 2.0 block — copy it from any existing workflow when adding a new one. This is an open-source repo; do not introduce a proprietary or confidential header.

## Lint & format (one-liner)

```bash
pre-commit run --all-files        # trailing-whitespace, eof, check-yaml, gitleaks, shellcheck, conventional-commit
hadolint scaleset/runner/Dockerfile scaleset/runner/Dockerfile.chainguard   # Dockerfile lint (if installed)
```

Full command surface is in `.claude/build-commands.md`. This repo has no compile step — there is no Gradle / Make / Task build at the repo root. Validation is pre-commit hooks locally and GitHub Actions in CI; the real "build" is `docker buildx`, exercised by the CI workflows.

## Two Dockerfiles, one build matrix

The runner image is built for **four base operating systems** from two Dockerfiles:

- `scaleset/runner/Dockerfile` — Debian/Ubuntu family, `apt`-based. Covers `ubuntu-22.04` (jammy), `ubuntu-24.04` (noble), `debian-bookworm` (bookworm-slim), built on `mcr.microsoft.com/dotnet/runtime-deps`.
- `scaleset/runner/Dockerfile.chainguard` — Chainguard Wolfi, `apk`-based, built on the internal Artifactory mirror (`artifacts.hashgraph.io/.../dotnet-runtime`). Covers `chainguard-wolfi` (`dev` tag).

`zxc-build-scaleset-images.yaml` selects the Dockerfile and maps `base-os-image → BASE_OS_VERSION` via `case(...)`. **Any change to one Dockerfile almost always needs the mirrored change in the other** — they install the same toolchain through different package managers (`apt` vs `apk`) and use different UID/GID for the `docker` group (123 vs 321). Keep the `## Begin/End ... Customizations ##` fenced sections aligned between the two files.

## Versioning & releases (don't hand-edit blindly)

- `scaleset/runner/VERSION` holds `CONTAINER_VERSION`, `RUNNER_VERSION`, `RUNNER_CONTAINER_HOOKS_VERSION`. It is **machine-updated** by the release flow (`update-version` job commits `chore(release): scaleset-v<x> [skip ci]`). Don't bump it by hand unless you intend to mimic a release.
- Versions are derived from upstream: `zxc-retrieve-upstream-versions.yaml` queries the latest `actions/runner` and `actions/runner-container-hooks` GitHub releases via `gh` + `semver`.
- `zxcron-automatic-releases.yaml` runs daily at 15:00 UTC: if upstream has a runner release with no matching `scaleset-v<version>` tag here, it dispatches `flow-release-scaleset-images.yaml` (non-dry-run) on `main`.
- A release builds all four images, pushes them to GHCR, updates `VERSION`, and creates a GitHub release `scaleset-v<version>` whose notes are imported from the upstream `actions/runner` release. Releases are blocked if the tag already exists (safety-checks job).

## When making changes

- **Add a tool to the image**: edit the `## OS Software Customizations ##` section in **both** Dockerfiles (apt in `Dockerfile`, apk in `Dockerfile.chainguard`). Pin versions via `ARG` with a default, mirroring the existing `GH_CLI_VERSION` / `YQ_CLI_VERSION` / `COMPOSE_VERSION` pattern, and pass the arg through `build-args` in `zxc-build-scaleset-images.yaml` if it should be overridable from CI.
- **Add a base OS**: extend the `base-os-image` matrix in `flow-pull-request-checks.yaml` AND `flow-release-scaleset-images.yaml`, and add the `base-os-image → BASE_OS_VERSION` mapping (and Dockerfile selection, if a new family) in the `case(...)` expressions of `zxc-build-scaleset-images.yaml`.
- **Add a tool-cache entry** (Java/Node/Go/etc. preloaded under `_work/_tool`): add a `Setup …` step to the `create-tool-cache` job in `zxc-build-scaleset-images.yaml`. The job archives `runner.tool_cache` into an artifact that the build job unpacks into `scaleset/runner/tools/` and the Dockerfile `COPY`s in.
- **New GitHub Actions workflow**: file under `.github/workflows/` following the existing prefix convention — `flow-*` for entry points (PR / release / scheduled-scan), `zxc-*` for reusable `workflow_call` callees, `zxcron-*` for `schedule`-triggered, `zxf-*` for fork-handling. Put the Apache 2.0 header on line 1, pin every `uses:` to a full SHA with a `# vX.Y.Z` trailing comment, add a `step-security/harden-runner` first step, and set explicit `permissions:` and `concurrency:`.
- **Never commit a secret.** Builds authenticate to GHCR via the workflow `GITHUB_TOKEN` and to Artifactory via JFrog OIDC — there are no plaintext credentials in the tree, and there should never be (`gitleaks` runs in pre-commit and CI).

## Commit policy (mandatory)

Every commit MUST be both **GPG-signed** and carry a **DCO `Signed-off-by:` trailer**, and PR/commit titles MUST follow Conventional Commits. The DCO trailer is auto-appended by the `prepare-commit-msg` hook and signing is git config — both are per-clone setup documented in [`.claude/git-hooks.md`](.claude/git-hooks.md). Never bypass with `--no-verify` or `--no-gpg-sign`. If a clone isn't configured for signing + DCO, set it up before committing rather than producing an unsigned commit.

## CI/CD

- **PR checks** (`flow-pull-request-checks.yaml`): builds all four images dry-run (`push: false`, single-arch `linux/amd64`) to prove the Dockerfiles still build against current upstream versions. Skipped on forks.
- **PR formatting** (`flow-pull-request-formatting.yaml`): enforces Conventional Commits PR titles.
- **Dependency review** (`flow-dependency-review.yml`) and **OpenSSF Scorecard** (`flow-ossf-scorecard.yml`): supply-chain / security posture checks.
- **Release** (`flow-release-scaleset-images.yaml`): `workflow_dispatch`, builds + pushes all four images to GHCR, updates `VERSION`, and cuts the `scaleset-v<x>` GitHub release. `dry-run-enabled` defaults true and is forced true off `main`.
- **Automatic releases** (`zxcron-automatic-releases.yaml`): daily upstream-version watcher that triggers the release flow.
- **Forked PRs** (`zxf-forked-pull-request-closer.yaml`): contributions from forks are auto-closed — this repo accepts changes only from trusted maintainers.
- **Reusable callees**: `zxc-build-scaleset-images.yaml` (the actual buildx build), `zxc-retrieve-upstream-versions.yaml` (upstream version resolution).
- **Actions hardening**: every `uses:` pinned by full SHA; every job opens with `step-security/harden-runner`. Dependabot updates GitHub Actions and the Docker base images daily.

## CODEOWNERS

- The global `*` catch-all is owned by `@hashgraph/release-engineering-managers` and `@hashgraph/product-security`.
- `/.github/workflows/` is co-owned by `@hashgraph/release-engineering-managers`, `@hashgraph/product-security`, and `@hashgraph/platform-ci`; the rest of `/.github/` by `@hashgraph/release-engineering-managers`.
- Root meta files (`README.md`, `LICENSE`, `.gitignore`, CODEOWNERS) and release config are owned by `@hashgraph/release-engineering-managers`.

## Things to leave alone unless asked

- `scaleset/runner/tools/` is a CI build artifact (the unpacked tool cache), not source — it is populated during the build and should not be committed.
- The `## Begin/End ... Customizations ##` comment fences in the Dockerfiles are load-bearing structure; keep them and keep the two Dockerfiles in sync rather than letting them drift.
- The split UID/GID for the `docker` group (123 in the Debian image, 321 in Chainguard) and the `1001` runner UID are deliberate — don't "normalize" them.
- Don't replace the Apache 2.0 license header with any other license.
