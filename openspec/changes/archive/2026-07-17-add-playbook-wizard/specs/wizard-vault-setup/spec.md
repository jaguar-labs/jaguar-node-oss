## ADDED Requirements

### Requirement: Vault step triggers only when needed and is skippable
After generating the playbook, if `vault/secrets.yaml` does not exist, the wizard SHALL offer to create it; the operator can decline, in which case the wizard prints the manual setup instructions (copy the example, edit, `ansible-vault encrypt`) and exits successfully. If `vault/secrets.yaml` already exists, the vault step SHALL be skipped silently.

#### Scenario: Vault already present
- **WHEN** `vault/secrets.yaml` exists at wizard run time
- **THEN** the wizard does not prompt for any secret and does not touch the vault file

#### Scenario: Operator declines
- **WHEN** the vault file is absent and the operator answers no to the vault step
- **THEN** the wizard exits zero, printing the manual vault setup steps from the README

### Requirement: Secrets are captured hidden and encrypted immediately
When the operator accepts the vault step, the wizard SHALL prompt for each key defined in `vault/secrets.example.yaml` (`telegraf_username`, `telegraf_password`, `pager_duty_key`, `solana_metrics_user`, `solana_metrics_password`) with terminal echo disabled for secret values, write `vault/secrets.yaml`, and immediately run `ansible-vault encrypt` on it. If encryption fails or is interrupted, the wizard SHALL delete the plaintext file before exiting. No plaintext secret SHALL remain on disk after the wizard exits, in any outcome.

#### Scenario: Successful vault creation
- **WHEN** the operator supplies all five values and a vault password
- **THEN** `vault/secrets.yaml` exists ansible-vault encrypted, and no unencrypted copy or temp file remains

#### Scenario: Encryption interrupted
- **WHEN** `ansible-vault encrypt` fails or the operator aborts (Ctrl-C) mid-step
- **THEN** the wizard's cleanup removes the plaintext `vault/secrets.yaml` and exits non-zero explaining nothing was saved
