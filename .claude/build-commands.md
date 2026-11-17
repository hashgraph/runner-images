# Key Build Commands

This repo holds no application code and no Gradle / Make / Task build at the root — CI compiles nothing. The real "build" is a Docker image build, and validation is pre-commit hooks plus GitHub Actions. The useful commands fall into three buckets: lint, local image build, and read-only inspection.

## Lint & format

CI and pre-commit drive these. Local commands mirror them:

- `pre-commit install && pre-commit install --hook-type commit-msg` — Install the hooks (see `.claude/git-hooks.md`).
- `pre-commit run --all-files` — Run every hook: trailing-whitespace, end-of-file-fixer, check-yaml, gitleaks, shellcheck, conventional-commit.
- `pre-commit run gitleaks --all-files` — Secret scan only.
- `pre-commit run shellcheck --all-files` — Shell lint only.
- `hadolint scaleset/runner/Dockerfile` — Dockerfile lint (Debian/Ubuntu variant).
- `hadolint scaleset/runner/Dockerfile.chainguard` — Dockerfile lint (Wolfi variant).
- `yamllint .github/workflows/` — YAML lint for workflows (if `yamllint` is installed).

## Building an image locally

The build args mirror what `zxc-build-scaleset-images.yaml` passes. CI prefills `scaleset/runner/tools/` with the tool cache; a bare local build will have an empty/absent tool cache, which is fine for testing the Dockerfile itself.

- Debian/Ubuntu variant (pick the `BASE_OS_VERSION`: `jammy` / `noble` / `bookworm-slim`):

  ```bash
  RUNNER_VERSION="$(grep '^RUNNER_VERSION=' scaleset/runner/VERSION | cut -d= -f2)"
  RUNNER_SHA256="$(gh api "repos/actions/runner/releases/tags/v${RUNNER_VERSION}" \
    --jq ".assets[] | select(.name == \"actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz\") | .digest" | sed 's/^sha256://')"

  docker buildx build \
    --file scaleset/runner/Dockerfile \
    --build-arg SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
    --build-arg RUNNER_VERSION="${RUNNER_VERSION}" \
    --build-arg RUNNER_SHA256="${RUNNER_SHA256}" \
    --build-arg BASE_OS_VERSION=noble \
    --platform linux/amd64 \
    --load -t scaleset-runner:local \
    scaleset/runner
  ```

  `SOURCE_DATE_EPOCH` is required: it selects the apt snapshot (the UTC day before the commit) and, with `--output type=...,rewrite-timestamp=true`, clamps file timestamps so the build is reproducible. `RUNNER_SHA256` is required; the container hooks, docker, buildx, gh, yq, and compose checksums default to the values pinned in the Dockerfile. Images are linux/amd64 only.

- Reproducibility check: build twice with `--no-cache --output type=oci,dest=<dir>,tar=false,rewrite-timestamp=true` and compare with `python3 -I .github/scripts/oci-image-report.py <dir> <report-dir>`; the two `digest.txt` files must match, and `diff` of the `files.tsv` reports names any file that differs.

- Chainguard Wolfi variant requires access to the internal Artifactory mirror (`artifacts.hashgraph.io`), so it generally only builds in CI where JFrog OIDC auth is available. Use `--file scaleset/runner/Dockerfile.chainguard` and `--build-arg BASE_OS_VERSION=dev`.
- `scaleset/runner/update-apk-lock.sh` — Regenerate `apk-packages.lock` (the exact Wolfi package closure) after editing `apk-packages.in` or the Chainguard base digest, or to pick up newer package builds. Needs docker and pull access to `artifacts.hashgraph.io`; no amd64 emulation required.

The `base-os-image → BASE_OS_VERSION` and Dockerfile selection live in the `case(...)` expressions in `zxc-build-scaleset-images.yaml`; mirror them when building by hand.

## Inspecting state (read-only)

Always allowed:

- `cat scaleset/runner/VERSION` — Current container / runner / hooks versions (machine-managed by the release flow).
- `gh release view --json tagName -R actions/runner` — Latest upstream runner version (what the cron watcher compares against).
- `gh release list -R hashgraph/runner-images` — Existing `scaleset-v*` releases.
- `gh run list` / `gh workflow list` — CI history and workflow inventory.
- `docker buildx ls`, `docker images`, `docker history scaleset-runner:local` — Local build introspection.

## Things this agent does NOT do without an explicit user request

- Push images to GHCR or any registry, run `flow-release-scaleset-images.yaml`, or otherwise cut a release.
- Hand-edit `scaleset/runner/VERSION` to fake a release (it is owned by the `update-version` job).
- Commit the contents of `scaleset/runner/tools/` (a CI build artifact, not source).
