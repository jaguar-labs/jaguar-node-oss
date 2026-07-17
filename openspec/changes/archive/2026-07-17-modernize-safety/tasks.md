# Tasks: modernize-safety

## 1. Secrets to Ansible Vault

- [x] 1.1 Create `vault/secrets.example.yaml` documenting keys: `telegraf_username`, `telegraf_password`, `pager_duty_key`, `solana_metrics_user`, `solana_metrics_password` (placeholder values, comment explaining `ansible-vault encrypt` workflow)
- [x] 1.2 Add `.gitignore` with rules excluding unencrypted local secrets (e.g. `vault/secrets.plain*.yaml`) — repo currently has no `.gitignore`
- [x] 1.3 Edit `playbooks/sample-testnet-profile.yaml`: add `vars_files: [../vault/secrets.yaml]`, remove plaintext `telegraf_username`/`telegraf_password`/`pager_duty_key` values, and rebuild `solana_metrics_url` to interpolate `{{ solana_metrics_user }}`/`{{ solana_metrics_password }}` from vault
- [x] 1.4 Verify with grep that no git-tracked file contains the old credential string (`c4fa841a...`), `thepassword`, or any other plaintext secret
- [x] 1.5 Add a README section: creating `vault/secrets.yaml` from the example, running with `--ask-vault-pass`/`--vault-password-file`, and a note that the previously committed metrics credential must be rotated by the operator

## 2. Playbook variable contract

- [x] 2.1 Add `entrypoints` (official testnet entrypoint list: `entrypoint.testnet.solana.com:8001`, `entrypoint2.testnet.solana.com:8001`, `entrypoint3.testnet.solana.com:8001`) to playbook `vars` next to `known_validators`
- [x] 2.2 Add `entrypoints is defined` and `entrypoints | length > 0` to the `pre_tasks` assertion block with a `fail_msg`
- [x] 2.3 Deduplicate the assertion list (`secrets_path`, `dynamic_port_range` each appear twice) and remove the tautological `jito.enabled | bool` assertion from the jito block (keep the `when:` guard and the per-key asserts)
- [x] 2.4 Statically review all three start-node templates to confirm `entrypoints` is the only playbook-level variable they reference that had no definition

## 3. Fix wired monitoring scripts

- [x] 3.1 Fix `roles/monitoring/files/output_validators.py`: `measurement_from_fields("validators", info, {}, config)`
- [x] 3.2 Fix `roles/monitoring/files/output_validators_info.py`: `measurement_from_fields("validators-info", info, {}, config)`
- [x] 3.3 Fix `roles/monitoring/files/output_gossip.py`: `measurement_from_fields("gossip", gossip, {}, config)`
- [x] 3.4 Run `python3 -m py_compile` over every file in the upload list and an import smoke test with a stub `monitoring_config` module (in scratchpad, not on hosts) to prove no `ImportError`/`TypeError` at import time

## 4. Delete dead code

- [x] 4.1 Delete `roles/common/tasks/ansible_user.yaml` (orphaned NOPASSWD sudo grant; confirm `roles/common/tasks/main.yaml` never imports it)
- [x] 4.2 Delete `roles/monitoring/tasks/install_telegraf_rpc.yaml` and `roles/monitoring/templates/telegraf.rpc.conf.j2` (orphaned; confirm `roles/monitoring/tasks/main.yaml` never imports the task file)
- [x] 4.3 Delete `roles/monitoring/files/validator_monitoring.py` and remove it from the upload list in `install_monitoring_script.yaml`
- [x] 4.4 Delete `roles/monitoring/files/tds_info.py`, `measurement_tds_info.py`, `output_tds_measurements.py` (never in the upload list)
- [x] 4.5 Grep the repo for any remaining references to the deleted files (task imports, telegraf configs, docs) and confirm none exist

## 5. Verification (static only — no local ansible-playbook runs)

- [x] 5.1 Confirm the upload list in `install_monitoring_script.yaml` exactly matches surviving files in `roles/monitoring/files/` (every listed file exists; every existing file is listed or imported by a listed one)
- [x] 5.2 Confirm the executed task set is unchanged: diff of role `main.yaml` files shows no import changes; only never-imported files were deleted
- [x] 5.3 Review the final playbook diff against the three spec files (secrets-management, playbook-variable-contract, monitoring-scripts-integrity) scenario by scenario
