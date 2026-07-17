# Proposal: modernize-safety

## Why

The repo currently ships plaintext credentials committed to git (a live-looking Solana metrics write credential and a telegraf password in `playbooks/sample-testnet-profile.yaml`), an undefined `entrypoints` variable that makes every run fail at template time unless supplied via `-e`, three telegraf-wired Python monitoring scripts that raise `TypeError` on first run, and orphaned files — including one that grants passwordless sudo — that look alive but are never imported. These are high-stakes, low-effort defects that must land before any broader modernization.

## What Changes

- Introduce Ansible Vault for all secrets: `telegraf_password`, `telegraf_username`, `pager_duty_key`, and the credential embedded in `solana_metrics_url`. The sample playbook loads them via `vars_files` from an encrypted vault file; a committed `.example` documents the expected keys. The committed metrics write credential is treated as compromised and removed from git-tracked plaintext (operator rotates it out-of-band).
- Define `entrypoints` per cluster in the sample playbook `vars` (official testnet entrypoints, next to `known_validators`, which follows the same per-cluster pattern) and add it to the `pre_tasks` assertion block with a clear `fail_msg`.
- Fix the `measurement_from_fields` call-arity bug in the three scripts wired into telegraf configs: `output_validators.py`, `output_validators_info.py`, `output_gossip.py` (they pass 3 args to a function whose signature is `(name, data, tags, config, legacy_tags=None)`).
- **BREAKING (dead-code removal — no runtime effect since none of it is imported/uploaded today):**
  - Delete `roles/common/tasks/ansible_user.yaml` (orphaned; grants `%ansible` NOPASSWD ALL sudo).
  - Delete `roles/monitoring/tasks/install_telegraf_rpc.yaml` and `roles/monitoring/templates/telegraf.rpc.conf.j2` (orphaned; pinned to 2019-era Telegraf 1.13, plaintext TimescaleDB creds).
  - Delete `roles/monitoring/files/validator_monitoring.py` (imports two modules that do not exist in the repo).
  - Delete `roles/monitoring/files/tds_info.py`, `measurement_tds_info.py`, `output_tds_measurements.py` (never uploaded; call an external kyc endpoint).
- Also remove the duplicated assertion entries (`secrets_path`, `dynamic_port_range` appear twice) and the tautological jito assert (`jito.enabled | bool` asserted under `when: jito.enabled | bool`) while editing the pre_tasks block.

## Capabilities

### New Capabilities

- `secrets-management`: How secrets are stored (Ansible Vault file loaded via `vars_files`), which variables are secret, what may never appear in plaintext in git, and the committed `.example` contract.
- `playbook-variable-contract`: Required variables the playbook must define and assert before roles run — including the previously undefined `entrypoints` list — and the rule that template-time variables must be asserted in `pre_tasks`.
- `monitoring-scripts-integrity`: Every Python file deployed to hosts must be importable and runnable; every script referenced by telegraf config must exist in the upload list; files not referenced anywhere are removed.

### Modified Capabilities

<!-- none — openspec/specs/ is empty; this change introduces the first specs -->

## Impact

- `playbooks/sample-testnet-profile.yaml` — secrets moved to vault, `entrypoints` added, assertion block cleaned up.
- New: `vault/secrets.yaml` (encrypted), `vault/secrets.example.yaml` (committed plaintext template), `.gitignore` entry for any unencrypted local secrets.
- `roles/monitoring/files/` — 3 scripts fixed, 4 deleted; `roles/monitoring/tasks/main.yaml` untouched (deleted task file was never imported).
- `roles/common/tasks/ansible_user.yaml` deleted; `roles/common/tasks/main.yaml` untouched (never imported it).
- Operator action required: rotate the exposed metrics write credential and set up a vault password out-of-band. Runs now require `--ask-vault-pass` or `--vault-password-file`.
- No change to what executes on hosts except the Python fixes (the deleted files never ran).
