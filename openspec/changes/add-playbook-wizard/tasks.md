# Tasks: add-playbook-wizard

## 1. Canonical template

- [x] 1.1 Create `playbooks/templates/profile.yaml.tmpl` from `sample-testnet-profile.yaml`, replacing validator-specific values with `@@TOKEN@@` placeholders (VALIDATOR_NAME, CLUSTER, IDENTITY_PUBKEY, VOTE_PUBKEY, LEDGER_DEV, ACCOUNTS_DEV, SNAPSHOTS_DEV, LOG_PATH, GENESIS_HASH, REMOTE_RPC, METRICS_PARAMS, ENTRYPOINTS_BLOCK, KNOWN_VALIDATORS_BLOCK, JITO_* block, XDP_* values)
- [x] 1.2 Add `playbooks/templates/` to `.yamllint` ignore (tokens are not valid YAML scalars everywhere) and confirm the CI syntax-check glob `playbooks/*.yaml` does not match the `.tmpl` file
- [x] 1.3 Document in a template header comment that this file is the canonical profile source and the sample playbook is generated from it

## 2. Wizard script

- [x] 2.1 Create `bin/new-playbook.sh` skeleton: bash strict mode, arg parsing (`--force`, `--help`), repo-root detection, trap-based cleanup (stty echo restore, partial-output removal)
- [x] 2.2 Implement prompt helpers: default-showing prompt, yes/no, hidden input, and validators (slug name, cluster enum, base58 pubkey 32-44 chars, `/dev/*` device path, absolute path)
- [x] 2.3 Embed cluster preset data for testnet and mainnet (entrypoints, known validators, genesis hash, remote RPC, metrics params, Jito endpoints + program pubkeys + NTP) with "last verified" comments; source mainnet values from Anza/Jito docs at implementation time
- [x] 2.4 Implement the essential prompts flow (name, cluster, pubkeys, disks, log path, jito y/n + commission/region, xdp y/n + interface/cores) with sample-profile defaults
- [x] 2.5 Implement generation: render answers + preset blocks, single awk substitution pass over the template, write `playbooks/<name>-<cluster>-profile.yaml`, refuse existing target without `--force`
- [x] 2.6 Implement self-checks: abort (and remove partial output) if any `@@` remains, naming the token; best-effort `python3 -c yaml.safe_load` parse when python3 exists
- [x] 2.7 Implement the optional vault step: trigger only when `vault/secrets.yaml` absent and `ansible-vault` present; parse key list from `vault/secrets.example.yaml`; hidden input; write + `ansible-vault encrypt`; trap guarantees plaintext removal on failure/interrupt

## 3. Round-trip proof and docs

- [x] 3.1 Regenerate `playbooks/sample-testnet-profile.yaml` using the wizard (scripted answers via stdin) and confirm the diff against the existing sample is empty or intentional; commit the regenerated file if it differs only cosmetically
- [x] 3.2 Add a README "Create a new validator profile" section: wizard usage, what it prompts, preset behavior, `--force`, vault step
- [x] 3.3 Run shellcheck on `bin/new-playbook.sh` and fix findings (add shellcheck to the CI lint job if trivially available via apt)

## 4. Verification (static + CI)

- [x] 4.1 Drive the wizard end-to-end with scripted stdin for: testnet defaults, mainnet with jito custom commission, xdp enabled, decline-vault, existing-target-without-force (expect abort) — inspecting generated files for correctness (no @@ tokens, valid YAML, correct presets)
- [x] 4.2 Verify vault-step cleanup: simulate encrypt failure (wrong confirm password / interrupt) and confirm no plaintext `vault/secrets.yaml` remains
- [x] 4.3 Commit a wizard-generated playbook on the branch and confirm CI (yamllint, ansible-lint, syntax-check with dummy vault) passes on it
