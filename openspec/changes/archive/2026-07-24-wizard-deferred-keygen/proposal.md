# Proposal: wizard-deferred-keygen

## Why

The wizard hard-requires base58 pubkeys for the validator identity and vote account — a wall for anyone provisioning a brand-new validator whose keys don't exist yet. The repo already generates the identity keypair on the host (`configure_node` runs `solana-keygen new` when the funded keypair is absent), so the natural design is deferral: let the operator answer `gen`/`skip`, ship the playbook with empty pubkey vars, and have the play fill them from the host-generated keypairs at run time.

## What Changes

- **Wizard prompts** (`bin/new-playbook.sh`):
  - Identity pubkey prompt accepts `gen` — the playbook is generated with `validator_identity_pubkey: ""` and the next-steps output explains the host will generate the keypair on first provisioning.
  - Vote account prompt accepts `skip` (or empty) — `vote_account_pubkey: ""`; next-steps prints the on-chain creation command the operator must run later (`solana create-vote-account ...`), the one step that cannot be automated.
- **Host-side backfill** (`roles/node-base/tasks/configure_node.yaml`):
  - After the existing identity keypair creation: read the pubkey (`solana-keygen pubkey`) and `set_fact: validator_identity_pubkey` when the play var is empty — `set_fact` outranks play vars, so the alerting role (watchtower `IDENTITY`) templates the real value.
  - When `vote_account_pubkey` is empty: generate `{{ secrets_path }}/vote-account-keypair.json` if absent (same pattern as the identity keypair) and `set_fact: vote_account_pubkey` from its pubkey, so monitoring config and alerting render the future vote account address.
- **Start script templates** (`start-node.sh.j2`, `start-node-jito.sh.j2`): the vote-account conditional changes from `{% if vote_account_pubkey is defined %}` to truthiness (`{% if vote_account_pubkey %}`) so an empty var falls to the already-existing else branch (`--vote-account {{ secrets_path }}/vote-account-keypair.json`) — the file the play now guarantees exists.
- Playbook assertions unchanged (vars stay defined; empty is a valid deferred state).
- README: document `gen`/`skip` and the on-chain vote-account creation step.

## Capabilities

### New Capabilities

- `validator-key-provisioning`: how validator keys come to exist — wizard deferral tokens, host-side generation and pubkey backfill via `set_fact`, the vote-account keypair file fallback in start scripts, and the operator's on-chain creation duty.

### Modified Capabilities

- `playbook-generation`: the essential-prompts requirement gains `gen` (identity) and `skip`/empty (vote account) as accepted answers.

## Impact

- `bin/new-playbook.sh`, `roles/node-base/tasks/configure_node.yaml`, both start-node templates, README.
- Behavior-preserving when pubkeys are supplied (today's path): the truthiness change only alters rendering for empty values, which previously produced a broken `--vote-account` arg (the old sample shipped `""` — this fixes a latent bug).
- Monitoring tolerates an on-chain-nonexistent vote account (metrics empty until created); watchtower will alert until the vote account is funded and voting — documented as expected during bootstrap.
