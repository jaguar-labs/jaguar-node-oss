# agave-source-install Specification

## Purpose
TBD - created by syncing change `build-cli-from-source`. Defines how the node-base role installs the agave CLI toolset by building from source (github.com + crates.io, never release.anza.xyz), how the build scope follows the Jito mode, and how Jito builds stay CLI-complete.

## Requirements

### Requirement: Agave is installed by building from source
The node-base role SHALL install agave by cloning `https://github.com/anza-xyz/agave.git` at tag `v{{ solana_version }}` (shallow clone) and running `scripts/cargo-install-all.sh` into `{{ solana_home }}/.local/share/solana/install/releases/{{ solana_version }}/solana-release`, as the `{{ solana_user }}` user. The role SHALL NOT download anything from `release.anza.xyz`. Build prerequisites (compiler toolchain, protobuf, Rust/cargo) SHALL be installed before the build runs.

#### Scenario: Fresh provisioning on a CDN-blocked host
- **WHEN** the playbook runs on a host that cannot reach release.anza.xyz
- **THEN** the install completes from github.com + crates.io sources only, and `active_release/bin/solana` reports version `{{ solana_version }}`

#### Scenario: Dev tools ordering
- **WHEN** node-base runs on a fresh host
- **THEN** build packages and Rust are installed before the agave build task executes

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

### Requirement: Idempotency and symlink safety
The build SHALL be skipped when `releases/{{ solana_version }}/solana-release/bin/solana` already exists (`creates:` guard), and the outer role guard SHALL check `active_release/bin/solana`. The role SHALL create the `active_release` symlink only when none exists; it SHALL never re-point an existing symlink (a Jito build owns the symlink once `build-jito.sh` has run).

#### Scenario: Re-run after successful provisioning
- **WHEN** the playbook re-runs on a provisioned host
- **THEN** no clone, build, or symlink task reports changed

#### Scenario: Re-run after Jito build
- **WHEN** `build-jito.sh` has pointed `active_release` at the Jito release and the playbook re-runs
- **THEN** the symlink still points at the Jito release afterwards

### Requirement: Jito builds are CLI-complete
`build-jito.sh` SHALL, after installing the Jito release and re-pointing `active_release`, copy any CLI binaries present in the vanilla release `bin/` but absent from the Jito release `bin/` (no-clobber copy), so that `solana`, `solana-keygen`, and the other operator tools resolve through `active_release/bin` in Jito mode.

#### Scenario: CLI available after Jito build
- **WHEN** `build-jito.sh` completes on a host provisioned by this role
- **THEN** `active_release/bin/solana` and `active_release/bin/solana-keygen` exist and run, alongside `agave-validator` from the Jito build
