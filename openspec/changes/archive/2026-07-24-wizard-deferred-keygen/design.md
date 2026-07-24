# Design: wizard-deferred-keygen

## Context

The wizard requires real pubkeys; new validators don't have them yet. `configure_node` already generates the identity keypair host-side when absent; the start templates already carry a vote-account-keypair-file else branch that today is unreachable (the var is always defined). Verified consumers: `validator_identity_pubkey` → playbook assert + alerting (watchtower `IDENTITY`); `vote_account_pubkey` → monitoring config + start scripts. Role order (node-base → validator → alerting → monitoring) means facts set in node-base reach every consumer.

## Goals / Non-Goals

**Goals:**
- `gen`/`skip` deferral tokens; playbooks ship empty vars; the play backfills real pubkeys at run time.
- Byte-identical outputs when pubkeys are supplied.

**Non-Goals:**
- Wizard-side keypair generation (rejected: creates a controller→host secret hand-off problem the host-side flow avoids entirely).
- On-chain transactions (vote account creation, funding) — printed instructions only.
- Vault storage of validator keypairs (they live in `{{ secrets_path }}`, as today).

## Decisions

1. **Defer to the host instead of generating in the wizard** (user decision). The identity generation task already exists; deferral means zero new secret-transport surface, and the keypair is born where it lives, `0700`-protected, owned by `solana`.
2. **Backfill via `set_fact`**, which outranks play vars — the empty play var acts as the "please fill me" sentinel. Guarded by `when: validator_identity_pubkey | length == 0` so supplied values are never touched. Reading the pubkey uses `solana-keygen pubkey` through the existing `env_path` environment pattern with `changed_when: false`.
3. **Vote-account keypair generation mirrors the identity task** (stat guard + `solana-keygen new -s --no-bip39-passphrase`), gated on the empty var. The start-template conditional flips from `is defined` to truthiness — reachable at last, and it fixes the latent broken-arg behavior for `""`.
4. **Assertions unchanged.** `is defined` still holds for empty strings; emptiness is now a meaningful deferred state, not an error. (Tightening non-deferred validation is possible later; out of scope.)
5. **Wizard tokens**: `gen` for identity (an empty answer stays invalid there — identity deferral should be explicit), `skip` or empty for the vote account (matching the historical `""` sample). Both print what will happen; the vote path prints the on-chain command in next-steps.
6. **Monitoring/alerting during bootstrap are expected to complain** (vote account not on-chain until created). Documented in README + next-steps rather than suppressed — silence would hide a real pending action.

## Risks / Trade-offs

- [Operator forgets the on-chain creation step] → watchtower alerts by design; next-steps + README state it; the validator simply doesn't vote until done — safe failure mode.
- [set_fact backfill misses a consumer templated before node-base] → Role order audited: no consumer runs before node-base (system-optimization/common don't use these vars).
- [Empty-var truthiness change surprises an existing playbook that shipped `""` deliberately] → The old rendering (`--vote-account` with empty value) was a startup failure; the new rendering is strictly better.
- [`solana-keygen` absent when backfill runs] → configure_node already asserts the CLI exists in env_path before any keygen use (added in the source-build change).

## Migration Plan

1. Wizard tokens + configure_node backfill/generation + template truthiness + README in one commit; sample round-trip (supplied pubkeys) must be an empty diff.
2. CI validates statically; the deferred path is exercised by scripted e2e (playbook generation side) — host-side backfill is verified by static task review per the no-local-ansible rule, then on the operator's next real provisioning run.
3. Rollback: revert; supplied-pubkey flows unaffected.

## Open Questions

- None.
