# Tasks: add-alpenglow-cluster

## 1. Template

- [x] 1.1 Add the `alpenglow` block (`enabled`, `expected_shred_version`, `expected_bank_hash` tokens) and the `@@DYNAMIC_PORT_RANGE@@` token to `profile.yaml.tmpl`; add alpenglow-gated assertions (shred version + bank hash non-empty) to `pre_tasks`
- [x] 1.2 Create `roles/validator/templates/start-node-alpenglow.sh.j2` from the reference field script: limit-ledger-size, expected-shred-version/bank-hash, do-not-require-vote-history, full-rpc-api, no jito/known-validator flags, deferred-vote file branch

## 2. Wizard

- [x] 2.1 Cluster prompt gains `alpenglow`; preset namespace (`preset_alpenglow_*`): IP entrypoints, genesis, remote RPC, metrics db/user/password, port range `9000-12500`, empty known validators, `solana_version 4.2.0-beta.0`; testnet/mainnet gain `dynamic_port_range` (`8000-10000`) and `solana_version` (`4.1.0-beta.3`) presets — template gains `@@DYNAMIC_PORT_RANGE@@` and `@@SOLANA_VERSION@@` tokens (watch_tower_version follows solana_version)
- [x] 2.2 Skip the Jito prompt on alpenglow (render `jito.enabled: False`); prompt `expected_shred_version` and `expected_bank_hash` with preset defaults and a check-latest warning; add both to next-steps warnings
- [x] 2.3 Handle empty known-validators rendering (template loop must emit nothing, and no `--only-known-rpc` in the alpenglow start template)

## 3. Roles

- [x] 3.1 `setup_validator.yaml`: three-way template selection (alpenglow > jito > standard); `utils_scripts.yaml`: deploy `build-alpenglow.sh` when alpenglow (jito script stays jito-gated)
- [x] 3.2 Create `roles/validator/files/build-alpenglow.sh` (style-aligned with build-jito.sh: package preflight, ref arg defaulting to `v4.2.0-beta.0` ("last verified" stamped, override allowed), `--validator-only`, symlink flip, `build-solana-cli.sh` hint when CLI absent); shellcheck-clean
- [x] 3.3 node-base build scope: `--no-build-validator-bins` when jito OR alpenglow; alerting watchtower skip-note condition extends to alpenglow

## 4. Docs

- [x] 4.1 README: alpenglow section (bootstrap order incl. `build-alpenglow.sh <ref>`, volatile-values caveat, no Jito)

## 5. Verification

- [x] 5.1 e2e: alpenglow generation — playbook parses; presets, port range, empty known validators, `jito.enabled: False`, shred/bank-hash values present; start template selected correctly (static render check of the template branch)
- [x] 5.2 Round-trip: testnet sample regeneration byte-identical (port-range token neutrality); mainnet spot-check unchanged
- [ ] 5.3 shellcheck (wizard + build-alpenglow.sh) + yamllint clean; commit, push, CI green