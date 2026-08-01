# Proposal: add-alpenglow-cluster

## Why

Anza's Alpenglow consensus test cluster is being validated on real nodes today with hand-written start scripts and a hand-rolled build script (both proven in the field and supplied as reference). The wizard only knows `testnet`/`mainnet`, so every alpenglow node means manual editing of exactly the values the wizard exists to manage — entrypoints, genesis hash, metrics credentials, port range — plus alpenglow-only flags no template carries.

## What Changes

- **Third cluster option: `alpenglow`** in the wizard's cluster prompt, with presets from the reference node:
  - Gossip entrypoints (IP-based): `64.130.37.11:8000`, `213.239.141.16:8001`
  - Genesis hash `HtRW7y9hJZaEBgH8cvUomQQjaXY5vM8J54nqbZJz7MjW`; remote RPC `http://185.8.106.234:8899`
  - Metrics: `db=alpenglow-testnet, u=ag, p=!d.tWEViQRhhP.*be9!a` (public cluster credentials, baked like the other clusters')
  - Dynamic port range `9000-12500` (differs from the 8000-10000 default → becomes a per-cluster preset with a new template token)
  - No known validators, **no Jito** (the Jito prompt is skipped and rendered disabled), DoubleZero off
- **Alpenglow start-script variant** (`start-node-alpenglow.sh.j2`, following the repo's per-variant template pattern): `--limit-ledger-size`, `--expected-shred-version`, `--expected-bank-hash`, `--do-not-require-vote-history`, `--full-rpc-api`, file-based `--vote-account` (the deferred-key branch), no known-validator/only-known-rpc flags. Selected by `setup_validator.yaml` three-ways (alpenglow > jito > standard).
- **Restart-sensitive values prompted, not hardcoded**: `expected_shred_version` and `expected_bank_hash` change when the test cluster restarts — the wizard prompts for them with the current presets as defaults and a warning to check the latest values; the playbook asserts them when alpenglow is enabled.
- **`build-alpenglow.sh`** deployed to alpenglow hosts (adapted from the field script, style-aligned with `build-jito.sh`): clones `anza-xyz/agave` at an arbitrary tag/branch (alpenglow releases are not normal version tags), builds `--validator-only`, re-points `active_release`, and prints the `build-solana-cli.sh` hint (the validator-only set lacks the CLI, same as Jito).
- node-base's source build treats alpenglow like jito (`--no-build-validator-bins` — the validator comes from `build-alpenglow.sh` at the alpenglow tag, not `v{{ solana_version }}`).

## Capabilities

### New Capabilities

- `alpenglow-cluster-support`: the alpenglow presets, the start-script flag set, restart-sensitive value handling, and the constraint set (no Jito, IP entrypoints, port range).

### Modified Capabilities

- `playbook-generation`: cluster prompt gains `alpenglow`; the presets requirement covers the third cluster (including per-cluster `dynamic_port_range`); Jito prompt conditional on cluster.
- `agave-source-install`: build scope extends to alpenglow (CLI-only in node-base, validator via `build-alpenglow.sh`); the deployed-build-scripts set gains the alpenglow script.

## Impact

- `bin/new-playbook.sh` (cluster enum, alpenglow presets, jito skip, shred/bank-hash prompts), `playbooks/templates/profile.yaml.tmpl` (alpenglow block + `@@DYNAMIC_PORT_RANGE@@` token), new `roles/validator/templates/start-node-alpenglow.sh.j2`, new `roles/validator/files/build-alpenglow.sh`, `setup_validator.yaml`, `utils_scripts.yaml`, node-base build-flag condition, playbook assertions, README.
- Existing testnet/mainnet flows byte-identical (round-trip guard, port-range token renders the old constant).
- Caveat surfaced, not hidden: alpenglow presets (entrypoints, shred version, bank hash) are volatile test-cluster data with a "last verified" stamp and prompt-time warnings.
