# Required local git hooks

Three things are **mandatory** on every fresh clone before you commit: the [pre-commit](https://pre-commit.com) framework (configured in `.pre-commit-config.yaml`), a hand-installed DCO `prepare-commit-msg` hook, and GPG commit signing. The hooks are not version-controlled under `.git/hooks/`, and signing is git config — set all three up per-clone. Commits that are unsigned or missing the DCO trailer are not acceptable.

## pre-commit framework

The pre-commit hooks are configured in `.pre-commit-config.yaml` at the repo root and installed per-clone from that config.

**On every fresh clone, install both hook types.** The `conventional-pre-commit` hook runs at the `commit-msg` stage, so the default `pre-commit install` (which only wires the `pre-commit` stage) is not enough on its own:

```bash
pip install pre-commit            # or: brew install pre-commit / pipx install pre-commit
pre-commit install                # wires the pre-commit stage hooks
pre-commit install --hook-type commit-msg   # wires the conventional-commit message check
```

## What the hooks enforce

From `.pre-commit-config.yaml`:

- **pre-commit-hooks** — `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-added-large-files`, `check-merge-conflict`, `detect-private-key`, `forbid-new-submodules`.
- **conventional-pre-commit** (`commit-msg` stage) — rejects commit messages that don't follow Conventional Commits. This mirrors the PR-title check in `flow-pull-request-formatting.yaml`.
- **gitleaks** — secret scanning; blocks commits that would introduce credentials.
- **shellcheck** — lints shell scripts and shell embedded in the repo.

## Working with the hooks

- Run the full suite on demand: `pre-commit run --all-files`.
- Update hook versions: `pre-commit autoupdate` (then commit the `.pre-commit-config.yaml` change as `build(deps)` / `chore(deps)`).
- Do **not** bypass hooks with `git commit --no-verify`. If a hook is wrong, fix the config or the content rather than skipping it.

## DCO Signed-off-by hook (mandatory)

Every commit MUST carry a [DCO](https://developercertificate.org) `Signed-off-by:` trailer. A `prepare-commit-msg` hook auto-appends it to non-merge, non-squash, non-amend commits. The hook lives at `.git/hooks/prepare-commit-msg` (per-clone, not version-controlled). It is required — install it on every fresh clone with the contents below and `chmod +x` it:

```bash
#!/bin/bash
# Auto-append DCO Signed-off-by line if not already present.
# Only applies to regular commits (not merges, squashes, or amends with -C).

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="$2"

case "${COMMIT_SOURCE}" in
  merge|squash|commit) exit 0 ;;
esac

SOB="Signed-off-by: $(git config user.name) <$(git config user.email)>"

if ! grep -qF "${SOB}" "${COMMIT_MSG_FILE}"; then
  echo "" >> "${COMMIT_MSG_FILE}"
  echo "${SOB}" >> "${COMMIT_MSG_FILE}"
fi
```

Don't commit it to the repo or use `core.hooksPath` — keep it under `.git/hooks/` per local convention.

## Commit signing (GPG) (mandatory)

Every contributor commit MUST be GPG-signed — no exceptions. Configure per-clone (or globally) so `%G?` shows `G` on `git log --show-signature`:

```bash
git config user.signingkey <YOUR-KEY-ID>   # long key id or full fingerprint
git config commit.gpgsign true
git config tag.gpgsign true
```

Use the key whose UID matches your configured `user.email`. Don't bypass signing with `--no-gpg-sign`. A commit that is not GPG-signed and DCO-signed-off does not meet this repo's commit policy and must be amended (re-signed) before it is pushed.
