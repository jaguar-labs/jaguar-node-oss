# secrets-management Specification

## Purpose
TBD - created by syncing change `modernize-safety`. Governs how secret values consumed by playbooks are stored, loaded, and documented.

## Requirements

### Requirement: Secrets are stored only in an encrypted vault file
All private secret values consumed by playbooks — currently `pager_duty_key` — SHALL live in an Ansible Vault encrypted file (`vault/secrets.yaml`) loaded via `vars_files`, and SHALL NOT appear in plaintext in any git-tracked file. Public/shared credentials — `solana_metrics_user`/`solana_metrics_password` (the per-cluster write credentials published in the Anza docs) and `telegraf_username`/`telegraf_password` (shared community metrics-backend values) — MAY appear in plaintext as role/example defaults; the vault file overrides them (play `vars_files` beat role defaults) for operators whose backends use private credentials.

#### Scenario: Playbook run with vault
- **WHEN** the operator runs the playbook with `--ask-vault-pass` or `--vault-password-file`
- **THEN** secret variables resolve from the encrypted vault file and all pre-task assertions pass

#### Scenario: Playbook run without vault password
- **WHEN** the operator runs the playbook without providing a vault password
- **THEN** Ansible fails before executing any role tasks, with an error indicating the vault file could not be decrypted

#### Scenario: Grep for secrets in tracked files
- **WHEN** git-tracked files are searched for the PagerDuty key
- **THEN** no plaintext private secret value is found (the public Anza metrics write credentials and the shared community telegraf credentials are exempt — they are documentation/default values, not private secrets)

### Requirement: A committed example file documents the vault contract
The repository SHALL contain a plaintext `vault/secrets.example.yaml` listing every expected secret key with placeholder values, and a `.gitignore` rule SHALL exclude unencrypted local secrets files (e.g. `vault/secrets.plain*.yaml`).

#### Scenario: New operator onboarding
- **WHEN** an operator clones the repository
- **THEN** `vault/secrets.example.yaml` shows every key they must provide, and copying it, filling values, and running `ansible-vault encrypt` produces a working `vault/secrets.yaml`
