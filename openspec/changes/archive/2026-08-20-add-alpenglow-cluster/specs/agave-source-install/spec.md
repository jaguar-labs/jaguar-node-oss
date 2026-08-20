## MODIFIED Requirements

### Requirement: Build scope follows the Jito mode
When `jito.enabled` is true, or the cluster is `alpenglow`, the agave build SHALL pass `--no-build-validator-bins` (CLI/operator tools only — the validator comes from the Jito or alpenglow build script respectively); otherwise it SHALL run a full build that includes `agave-validator`.

#### Scenario: Non-Jito host has a validator after provisioning
- **WHEN** the playbook runs with `jito.enabled: false` on testnet or mainnet
- **THEN** `active_release/bin/agave-validator` exists and reports `{{ solana_version }}`

#### Scenario: Jito host builds CLI only in node-base
- **WHEN** the playbook runs with `jito.enabled: true`
- **THEN** the node-base build produces the CLI toolset without the validator, and the operator-run `build-jito.sh` supplies `agave-validator`

#### Scenario: Alpenglow host builds CLI only in node-base
- **WHEN** the playbook runs for the alpenglow cluster
- **THEN** the node-base build produces the CLI toolset without the validator, and the operator-run `build-alpenglow.sh` supplies `agave-validator` at the cluster's agave ref
