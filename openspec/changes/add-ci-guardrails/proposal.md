# Proposal: add-ci-guardrails

## Why

The repo has zero automated checks — no lint config, no CI, no pinned collection dependencies — and its git history (`fix`, `fix`, `fix`, `fix` on the upgrade branch) shows regressions are currently caught by running against real validator infrastructure. Since the project convention forbids running `ansible-playbook` on the controller, CI is the only place checks can execute; adding it is the multiplier that makes every later modernization track (idiom sweep, sysctl reconciliation) safely reviewable.

## What Changes

- Add `requirements.yml` pinning the collections actually used (`community.general`, `ansible.posix`) with version ranges, replacing the README's manual `ansible-galaxy collection install` instruction.
- Add `.yamllint` and `.ansible-lint` configs. Target profile is ansible-lint `production`; rules the current codebase cannot yet satisfy (FQCN, `with_items`, `changed_when`, etc. — the future idiom-sweep track) go in a documented `skip_list`/`warn_list` so CI is green from day one and the skip list shrinks as tracks land.
- Add a GitHub Actions workflow running on push/PR: `yamllint`, `ansible-lint`, and `ansible-playbook --syntax-check` on every playbook (with `--ask-vault-pass` bypassed via a dummy vault password and dummy vault file, since `modernize-safety` introduces `vars_files` vault loading).
- Update README: correct the quick-start (the referenced `full-validator-mainnet-profile.yaml` does not exist — point at the real playbook), install deps via `ansible-galaxy install -r requirements.yml`, add a CI badge.

## Capabilities

### New Capabilities

- `dependency-pinning`: Collection dependencies are declared and pinned in `requirements.yml`; documentation installs from it.
- `ci-static-checks`: Every push/PR runs yamllint, ansible-lint (production profile with documented skips), and playbook syntax-check in CI; no Ansible execution happens on operator controllers as part of verification.

### Modified Capabilities

<!-- none — no existing specs cover these areas -->

## Impact

- New files: `requirements.yml`, `.yamllint`, `.ansible-lint`, `.github/workflows/ci.yaml`, CI dummy vault inputs.
- `README.md` — corrected quick-start, dependency install step, badge.
- No role/playbook logic changes and no change to host behavior; depends on `modernize-safety` only for the vault-aware syntax-check step (can land in either order if the CI vault step is written defensively).
