# Design: add-playbook-wizard

## Context

Provisioning a new validator means hand-editing a copy of `playbooks/sample-testnet-profile.yaml`. Since `modernize-safety`, playbooks have a strict variable contract (asserted in `pre_tasks`) and load secrets from an encrypted vault; since `add-ci-guardrails`, everything under `playbooks/*.yaml` is lint- and syntax-checked in CI. The wizard is controller-side tooling: it generates files but never invokes `ansible-playbook` (project rule) — CI validates its output.

## Goals / Non-Goals

**Goals:**
- One interactive run produces a correct, CI-passing playbook for testnet or mainnet.
- Cluster presets are the single embedded source for entrypoints/known-validators/genesis/Jito endpoints.
- Optional vault bootstrap with zero plaintext residue.

**Non-Goals:**
- Generating RPC-node profiles (validator profiles only for now; the rpc role has no playbook story yet).
- Editing existing playbooks (generation only; re-run with `--force` to regenerate).
- Non-interactive/flag-driven mode (could be added later; prompts-with-defaults is the contract now).
- Running or validating with Ansible from the wizard.

## Decisions

1. **Bash with POSIX-ish discipline, no dependencies beyond coreutils + ansible-vault.** The repo's operator tooling is already shell (`start-node.sh`, `node-transition.sh`); Python would add a runtime expectation the controller may not meet. `#!/usr/bin/env bash`, `set -euo pipefail`.
2. **Template + `@@TOKEN@@` substitution, not heredoc** (user decision). Template lives at `playbooks/templates/profile.yaml.tmpl`, derived from the sample profile. The `.tmpl` extension plus `templates/` subdirectory keeps it out of CI's `playbooks/*.yaml` syntax-check glob; a yamllint ignore entry is added since `@@TOKEN@@` values would parse oddly. Substitution via a single `awk` pass over a `KEY=VALUE` answers file rendered in-memory — avoids sed-escaping pitfalls with slashes in URLs/paths.
3. **List-valued presets (entrypoints, known_validators) are substituted as pre-rendered YAML blocks**, not scalar tokens — the wizard builds the indented block per cluster and injects it at `@@ENTRYPOINTS_BLOCK@@`/`@@KNOWN_VALIDATORS_BLOCK@@`. Keeps the template honestly YAML-shaped while allowing variable-length lists.
4. **Cluster presets live in the wizard script as two shell "namespaces"** (`preset_testnet_*`, `preset_mainnet_*` variables). Alternative — a separate presets data file — rejected: one more file to drift; the script is the natural home and diffs cleanly. Preset values are sourced from the current sample profile (testnet) and official Anza/Jito documentation (mainnet), pinned at implementation time and reviewable in the PR.
5. **Post-generation self-check inside the wizard**: (a) no `@@` remains; (b) if `python3` is available, parse the output with `yaml.safe_load` as a best-effort local check (skipped silently if absent). Full validation stays in CI.
6. **Vault step reuses the `vault/secrets.example.yaml` key list** by parsing its top-level keys, so the wizard never hardcodes the secret contract (single-sourced per the secrets-management spec). Hidden input via `read -rs`; `trap` on EXIT/INT removes plaintext if `ansible-vault encrypt` did not complete.
7. **Filename convention `<validator-name>-<cluster>-profile.yaml`** mirrors the existing `sample-testnet-profile.yaml` pattern; the validator name is slugified (lowercase, `[a-z0-9-]` only) to keep filenames and CI globs predictable.

## Risks / Trade-offs

- [Cluster presets go stale (entrypoints, known validators, Jito endpoints change)] → Presets are data at the top of one script with a "last verified" comment; wizard prints a reminder to review presets for mainnet; wrong entrypoints fail loudly at validator start, not silently.
- [Template and sample playbook drift apart] → The template *replaces* the sample as canonical source going forward; task includes regenerating `sample-testnet-profile.yaml` via the wizard itself to prove round-trip fidelity, and a README note marks the sample as wizard-generated.
- [awk substitution corrupts on exotic input (backslashes, `&`)] → Values are validated against conservative character allowlists before substitution (pubkeys are base58; device paths `/dev/...`; names slugified), so hostile input is rejected at prompt time.
- [Vault step runs `ansible-vault`, which may be absent on a fresh controller] → Checked up front; vault step is offered only if the binary exists, otherwise manual instructions are printed.
- [Ctrl-C during hidden prompts leaves terminal echo off] → `trap` restores terminal state (`stty echo`) on any exit path.

## Migration Plan

1. Land template + wizard + README section in one commit on the working branch; CI validates the regenerated sample playbook.
2. No host-side or operator migration: existing playbooks keep working; the wizard is additive tooling.
3. Rollback: delete `bin/new-playbook.sh` and the template; the sample playbook remains valid either way.

## Open Questions

- None blocking. Mainnet known-validator preset list (which pubkeys to embed) is chosen at implementation time from Anza's documented bootstrap set and flagged for review in the PR.
