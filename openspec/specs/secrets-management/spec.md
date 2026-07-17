# secrets-management Specification

## Purpose
TBD - created by syncing change `modernize-safety`. Governs how secret values consumed by playbooks are stored, loaded, and documented.

## Requirements

### Requirement: Secrets are stored only in an encrypted vault file
All secret values consumed by playbooks — `telegraf_username`, `telegraf_password`, `pager_duty_key`, and the write credential embedded in `solana_metrics_url` — SHALL live in an Ansible Vault encrypted file (`vault/secrets.yaml`) loaded via `vars_files`. No secret value SHALL appear in plaintext in any git-tracked file.

#### Scenario: Playbook run with vault
- **WHEN** the operator runs the playbook with `--ask-vault-pass` or `--vault-password-file`
- **THEN** secret variables resolve from the encrypted vault file and all pre-task assertions pass

#### Scenario: Playbook run without vault password
- **WHEN** the operator runs the playbook without providing a vault password
- **THEN** Ansible fails before executing any role tasks, with an error indicating the vault file could not be decrypted

#### Scenario: Grep for secrets in tracked files
- **WHEN** git-tracked files are searched for the telegraf password, PagerDuty key, or metrics URL credential
- **THEN** no plaintext secret value is found (the previously committed metrics write credential `u=testnet_write,p=...` is removed and treated as compromised)

### Requirement: A committed example file documents the vault contract
The repository SHALL contain a plaintext `vault/secrets.example.yaml` listing every expected secret key with placeholder values, and a `.gitignore` rule SHALL exclude unencrypted local secrets files (e.g. `vault/secrets.plain*.yaml`).

#### Scenario: New operator onboarding
- **WHEN** an operator clones the repository
- **THEN** `vault/secrets.example.yaml` shows every key they must provide, and copying it, filling values, and running `ansible-vault encrypt` produces a working `vault/secrets.yaml`
