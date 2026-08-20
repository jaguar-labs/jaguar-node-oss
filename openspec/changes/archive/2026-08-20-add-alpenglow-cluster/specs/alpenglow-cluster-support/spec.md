## ADDED Requirements

### Requirement: Alpenglow start script carries the cluster's flag set
Alpenglow playbooks SHALL render a dedicated start script (`start-node-alpenglow.sh.j2`, selected by `setup_validator.yaml` when the alpenglow cluster is chosen) containing: `--limit-ledger-size`, `--expected-shred-version {{ expected_shred_version }}`, `--expected-bank-hash {{ expected_bank_hash }}`, `--do-not-require-vote-history`, `--full-rpc-api`, the standard identity/ledger/accounts/snapshots/log/port-range/entrypoint arguments, and a file-based `--vote-account` when the vote pubkey is deferred. It SHALL NOT contain Jito flags, `--known-validator`, or `--only-known-rpc`.

#### Scenario: Rendered alpenglow start script
- **WHEN** an alpenglow playbook is deployed
- **THEN** the start script matches the reference field script's flag set with the playbook's values substituted, and contains no Jito or known-validator arguments

#### Scenario: Restart-sensitive values asserted
- **WHEN** an alpenglow playbook runs with `expected_shred_version` or `expected_bank_hash` undefined or empty
- **THEN** the pre-task assertions fail naming the missing variable (these values change on cluster restarts and must be explicit)

### Requirement: Alpenglow validator builds from an arbitrary agave ref
Alpenglow hosts SHALL receive `build-alpenglow.sh` (deployed like `build-jito.sh`, style-aligned with it): it clones `anza-xyz/agave` at a tag or branch defaulting to the cluster's current ref (`v4.2.0-beta.0`, "last verified" stamped) with an optional argument to override, builds with `cargo-install-all.sh --validator-only` into `releases/<ref>`, re-points `active_release`, and prints the `build-solana-cli.sh` hint when the CLI tools are absent (the validator-only set has none). node-base's source build SHALL treat alpenglow like Jito (`--no-build-validator-bins` — CLI only, at the alpenglow `solana_version` preset `4.2.0-beta.0`; the validator comes from the alpenglow build).

#### Scenario: Alpenglow bootstrap sequence
- **WHEN** a fresh alpenglow host is provisioned
- **THEN** node-base builds CLI tools only, the playbook deploys `build-alpenglow.sh`, and running it with the cluster's current ref produces `agave-validator` in `active_release` (alerting's watchtower note applies as on Jito hosts until then)

#### Scenario: Default ref with override
- **WHEN** `build-alpenglow.sh` runs without an argument
- **THEN** it builds the stamped default ref `v4.2.0-beta.0`, printing which ref it is using; an explicit argument overrides it

### Requirement: Volatile presets are stamped and warned
The alpenglow presets (entrypoints, genesis hash, remote RPC, shred version, bank hash) SHALL carry a "last verified" date comment in the wizard, and the wizard's alpenglow next-steps SHALL warn that these are test-cluster values that change on restarts, pointing at where to obtain current ones.

#### Scenario: Wizard surfaces volatility
- **WHEN** the operator completes an alpenglow wizard run
- **THEN** the next-steps output includes the check-latest-values warning for the restart-sensitive parameters
