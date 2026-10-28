# Spec Delta

## MODIFIED Requirements

### Requirement: Alpenglow start script carries the cluster's flag set
Alpenglow playbooks SHALL render a dedicated start script (`start-node-alpenglow.sh.j2`, selected by `setup_validator.yaml` when the alpenglow cluster is chosen) containing: `--limit-ledger-size`, `--expected-shred-version {{ expected_shred_version }}`, `--expected-bank-hash {{ expected_bank_hash }}`, `--full-rpc-api`, `--authorized-voter` naming the funded identity keypair, the standard identity/ledger/accounts/snapshots/log/port-range/entrypoint arguments, and a file-based `--vote-account` when the vote pubkey is deferred. It SHALL NOT contain Jito flags, `--known-validator`, `--only-known-rpc`, or `--do-not-require-vote-history`: with Alpenglow live on every cluster, a start script that skips the vote history check would let a node vote without its history after a failover; the flag belongs only to the gated emergency hand-over.

#### Scenario: Rendered alpenglow start script
- **WHEN** an alpenglow playbook is deployed
- **THEN** the start script matches the reference field script's flag set with the playbook's values substituted, includes `--authorized-voter` with the funded keypair path, and contains no Jito, known-validator or `--do-not-require-vote-history` arguments

#### Scenario: Restart-sensitive values asserted
- **WHEN** an alpenglow playbook runs with `expected_shred_version` or `expected_bank_hash` undefined or empty
- **THEN** the pre-task assertions fail naming the missing variable (these values change on cluster restarts and must be explicit)
