# Proposal: add-playbook-wizard

## Why

Creating a playbook for a new validator today means copying the 190-line `sample-testnet-profile.yaml` and hand-editing pubkeys, disk devices, cluster endpoints, and Jito settings scattered through it — error-prone (the repo's own history shows repeated fix commits from config drift), and cluster-specific values like entrypoints, known validators, and genesis hashes must be looked up each time. An interactive wizard that asks only for validator-specific values and fills in correct cluster presets makes new-node provisioning fast and self-consistent.

## What Changes

- Add a `bin/new-playbook.sh` interactive shell wizard (bash, controller-side tooling — it never runs Ansible) that:
  - Prompts for ~10 essential values: validator name, cluster (testnet/mainnet), identity pubkey, vote account pubkey, disk devices for ledger/accounts/snapshots, log path, Jito enabled (plus commission/region if yes), XDP enabled (plus interface if yes).
  - Auto-fills cluster presets from the chosen cluster: gossip entrypoints, known validators, expected genesis hash, cluster RPC addresses, solana metrics database, Jito block-engine/shred-receiver/NTP endpoints.
  - Generates `playbooks/<validator-name>-<cluster>-profile.yaml` by substituting `@@TOKEN@@` placeholders in a committed canonical template; refuses to overwrite an existing playbook without `--force`.
  - Offers an optional vault step: if `vault/secrets.yaml` is absent, prompts for the five secret values with hidden input, writes the file, and immediately runs `ansible-vault encrypt` on it; no unencrypted secret remains on disk after the wizard exits.
- Add `playbooks/templates/profile.yaml.tmpl` — the canonical template derived from `sample-testnet-profile.yaml` with `@@TOKEN@@` placeholders, plus per-cluster preset data embedded in the wizard.
- Wizard output passes the existing CI checks (yamllint; `ansible-playbook --syntax-check` covers `playbooks/*.yaml`, so generated playbooks are checked once committed).

## Capabilities

### New Capabilities

- `playbook-generation`: The wizard's contract — what it prompts for, what presets each cluster supplies, what file it produces, overwrite safety, and that generated output satisfies the existing `playbook-variable-contract` spec (all required vars defined, entrypoints non-empty).
- `wizard-vault-setup`: The optional secrets step — when it triggers, hidden input, immediate encryption, and the guarantee that no plaintext secret survives the wizard run.

### Modified Capabilities

<!-- none — existing specs (secrets-management, playbook-variable-contract, monitoring-scripts-integrity) are consumed as constraints, not changed -->

## Impact

- New files: `bin/new-playbook.sh`, `playbooks/templates/profile.yaml.tmpl`, README section on wizard usage.
- CI: template file must be excluded from the `playbooks/*.yaml` syntax-check glob (it lives under `playbooks/templates/` with a `.tmpl` extension, so the existing `playbooks/*.yaml` glob already skips it) and from ansible-lint/yamllint noise if needed.
- No role changes; no change to host behavior. Depends on conventions established by `modernize-safety` (vault contract, entrypoints variable) — both already landed.
