# Directory Structure

This repository builds **container images** for GitHub Actions self-hosted runners. The layout is small and Docker/Actions-centric:

## Top-level

- `scaleset/runner/` — Everything that defines the runner image.
   - `Dockerfile` — Debian/Ubuntu (`apt`) variant, built on `mcr.microsoft.com/dotnet/runtime-deps`. Multi-stage: stage 1 downloads the upstream `actions/runner`, `runner-container-hooks`, docker CLI, and buildx; the final stage installs the toolchain and creates the `runner` user (UID 1001, `docker` GID 123). Covers `ubuntu-22.04` / `ubuntu-24.04` / `debian-bookworm`.
   - `Dockerfile.chainguard` — Chainguard Wolfi (`apk`) variant, built on the internal Artifactory mirror (`artifacts.hashgraph.io/.../dotnet-runtime`). Same toolchain, different package manager, `docker` GID 321. Covers `chainguard-wolfi`.
   - `VERSION` — `CONTAINER_VERSION`, `RUNNER_VERSION`, `RUNNER_CONTAINER_HOOKS_VERSION`. Machine-managed by the release flow's `update-version` job; do not hand-edit casually.
   - `tools/` — Drop target for the CI **tool cache** (Java, Node, Go, Kind, Helm, Terraform, buildx). Populated at build time from a CI artifact and `COPY`d into the image at `/home/runner/_work/_tool`. This is a build artifact, not source — not committed.
- `.github/` — Repository configuration and all automation.
   - `.github/workflows/` — CI/CD workflows. Filename prefixes signal role:
      - `flow-*` — entry points. `flow-pull-request-checks.yaml` (dry-run build matrix), `flow-pull-request-formatting.yaml` (Conventional Commits title check), `flow-release-scaleset-images.yaml` (`workflow_dispatch` release), `flow-dependency-review.yml`, `flow-ossf-scorecard.yml`.
      - `zxc-*` — reusable `workflow_call` callees. `zxc-build-scaleset-images.yaml` (the buildx build + tool-cache job), `zxc-retrieve-upstream-versions.yaml` (resolve upstream runner/hooks versions).
      - `zxcron-*` — `schedule`-triggered. `zxcron-automatic-releases.yaml` (daily upstream-version watcher → dispatches the release flow).
      - `zxf-*` — fork handling. `zxf-forked-pull-request-closer.yaml` (auto-closes PRs from forks).
   - `.github/CODEOWNERS` — Review ownership; `@hashgraph/release-engineering-managers` + `@hashgraph/product-security` globally, with `@hashgraph/platform-ci` co-owning workflows.
   - `.github/dependabot.yml` — Daily updates for `github-actions` and the `docker` base images under `/scaleset/runner`.
   - `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md` — Contribution templates.
- `.pre-commit-config.yaml` — Local hook definitions (trailing-whitespace, eof, check-yaml, gitleaks, shellcheck, conventional-commit). See `.claude/git-hooks.md`.
- `README.md`, `LICENSE` — Apache 2.0. Contributions from forks are not accepted; changes come from trusted maintainers only.

## The build pipeline at a glance

1. `zxc-retrieve-upstream-versions.yaml` resolves the latest `actions/runner` + `actions/runner-container-hooks` versions (or validates explicit overrides).
2. `zxc-build-scaleset-images.yaml` builds the tool cache, then runs `docker buildx` for one `base-os-image`, selecting `Dockerfile` vs `Dockerfile.chainguard` and the `BASE_OS_VERSION` via `case(...)`.
3. `flow-pull-request-checks.yaml` fans that build across all four base OSes as a dry run on every PR; `flow-release-scaleset-images.yaml` does the same with push enabled, then updates `VERSION` and cuts the `scaleset-v<x>` GitHub release.
4. `zxcron-automatic-releases.yaml` triggers (3) automatically when upstream ships a new runner.

As the repository grows (new base images, new Dockerfiles, new workflows), update this file to describe the concrete contents.
