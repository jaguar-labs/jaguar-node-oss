# Tasks: wizard-deferred-keygen

## 1. Wizard prompts

- [x] 1.1 Identity prompt: accept `gen` alongside base58 (explicit token, empty stays invalid); sets `IDENTITY_PUBKEY=""` and remembers deferral for next-steps
- [x] 1.2 Vote prompt: accept `skip` or empty alongside base58; sets `VOTE_PUBKEY=""` and remembers deferral
- [x] 1.3 Next-steps output: when identity deferred, note the host generates `funded-validator-keypair.json` during provisioning; when vote deferred, print the exact `solana create-vote-account {{ secrets_path }}/vote-account-keypair.json {{ secrets_path }}/funded-validator-keypair.json <WITHDRAWER_ADDRESS>` command and the watchtower-alerts-until-created caveat

## 2. Host-side backfill (configure_node)

- [x] 2.1 After the identity keypair task: read its pubkey (`solana-keygen pubkey`, `changed_when: false`, env_path environment) and `set_fact: validator_identity_pubkey` guarded by `when: validator_identity_pubkey | length == 0`
- [x] 2.2 Vote-account keypair: stat + `solana-keygen new -s --no-bip39-passphrase -o {{ secrets_path }}/vote-account-keypair.json` guarded on empty `vote_account_pubkey`; then `set_fact: vote_account_pubkey` from its pubkey under the same guard
- [x] 2.3 Static review: confirm no consumer of either var is templated before node-base in role order

## 3. Start-script templates

- [x] 3.1 `start-node.sh.j2` + `start-node-jito.sh.j2`: `{% if vote_account_pubkey is defined %}` → `{% if vote_account_pubkey %}` (else branch: keypair file path, unchanged)

## 4. Docs

- [x] 4.1 README: `gen`/`skip` tokens, what the host generates, the on-chain creation step, expected bootstrap alerting

## 5. Verification

- [x] 5.1 Round-trip: sample regeneration with supplied pubkeys — empty diff (prompt changes must not alter supplied-value output)
- [x] 5.2 Scripted e2e: `gen` + `skip` run — playbook has both vars empty, parses, next-steps contains the create-vote-account command; invalid tokens still re-prompt
- [x] 5.3 Rendered-template check (static): with an empty vote var the start-script template logic selects the keypair-file branch (verify via a python/jinja render of the template snippet or grep-level assertion of the generated playbook + template pairing)
- [x] 5.4 shellcheck + yamllint (+ pinned ansible-lint if available) clean; commit, push, CI green; flag that host-side backfill is validated on the next real provisioning run
