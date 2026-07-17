# playbook-generation Specification

## Purpose
TBD - created by syncing change `add-playbook-wizard`. Defines the interactive wizard that generates validator playbooks from the committed template, prompting only for validator-specific essentials and filling cluster presets automatically.

## Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey, vote account pubkey, ledger/accounts/snapshots disk devices, validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, pubkey that is not 32-44 base58 characters)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

### Requirement: Cluster choice supplies correct presets
Selecting a cluster SHALL auto-fill, without prompting: gossip entrypoints, known validators, expected genesis hash, remote cluster RPC address, solana metrics database parameters, and — when Jito is enabled — the cluster-appropriate block-engine URL, shred receiver address, tip payment/distribution program pubkeys, merkle root upload authority, and Jito NTP server.

#### Scenario: Testnet presets
- **WHEN** the operator selects `testnet`
- **THEN** the generated playbook contains the testnet entrypoints (`entrypoint*.testnet.solana.com:8001`), testnet genesis hash `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY`, and testnet Jito endpoints if Jito is enabled

#### Scenario: Mainnet presets
- **WHEN** the operator selects `mainnet`
- **THEN** the generated playbook contains mainnet entrypoints, the mainnet genesis hash `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d`, mainnet known validators, and mainnet Jito endpoints if Jito is enabled

### Requirement: Generation is template-based and overwrite-safe
The playbook SHALL be produced by substituting `@@TOKEN@@` placeholders in the committed template `playbooks/templates/profile.yaml.tmpl`, written to `playbooks/<validator-name>-<cluster>-profile.yaml`. If the target file exists, the wizard SHALL abort with a message unless `--force` is passed. After substitution the wizard SHALL verify no `@@` placeholder remains in the output.

#### Scenario: Target exists without --force
- **WHEN** the wizard would write a playbook path that already exists and `--force` was not given
- **THEN** it exits non-zero without modifying the file, telling the operator to re-run with `--force` to overwrite

#### Scenario: Unsubstituted placeholder detection
- **WHEN** substitution completes but a `@@TOKEN@@` remains (e.g. template gained a new token the wizard does not know)
- **THEN** the wizard deletes the partial output and exits non-zero naming the unfilled token

### Requirement: Generated playbooks satisfy the playbook variable contract
Generated output SHALL parse as valid YAML and define every variable required by the `playbook-variable-contract` spec, including a non-empty `entrypoints` list, and SHALL load secrets via `vars_files: ../vault/secrets.yaml` exactly as the sample profile does.

#### Scenario: Generated playbook passes CI
- **WHEN** a generated playbook is committed and CI runs
- **THEN** yamllint and `ansible-playbook --syntax-check` (with the dummy vault) pass without modification
