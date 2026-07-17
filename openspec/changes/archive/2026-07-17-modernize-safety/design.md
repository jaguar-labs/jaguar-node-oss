# Design: modernize-safety

## Context

The repo provisions live Solana validator/RPC nodes. Discovery found four safety defects: plaintext credentials committed to git (including a live-looking metrics write credential at `playbooks/sample-testnet-profile.yaml:134`), an `entrypoints` variable referenced by all three start-node templates but defined nowhere, three uploaded monitoring scripts that raise `TypeError` on invocation, and orphaned files that look alive — one of which grants NOPASSWD sudo. Standing constraints: never run `ansible-playbook` on the controller (static analysis only), and nothing may auto-restart the validator.

## Goals / Non-Goals

**Goals:**
- No plaintext secret in any git-tracked file; vault-based loading with a committed example contract.
- Every variable a template needs is defined in the playbook and asserted in `pre_tasks`.
- Everything deployed to hosts imports and runs; everything unreachable is deleted.
- Zero change to the set of tasks executed on hosts (deletions are of never-imported files).

**Non-Goals:**
- FQCN/loop/lint modernization (separate `add-ci-guardrails` change and later idiom sweep).
- sysctl/tuned reconciliation, snapshot/zstd staleness, broader Python quality (bare `except:`, `shell=True`) — track 4.
- Rotating the exposed metrics credential itself — operator action out-of-band; this change removes it from git.

## Decisions

1. **Vault layout: `vault/secrets.yaml` (encrypted) + `vault/secrets.example.yaml` (committed).** Loaded via `vars_files` in the playbook. Alternative — gitignored plaintext vars file — rejected per user decision: nothing encrypted at rest. Alternative — `-e`/env injection — rejected: every run must supply values, drift-prone.
2. **`solana_metrics_url` is split.** The URL keeps its non-secret shape in playbook vars with the credential interpolated from vault vars (`solana_metrics_user`, `solana_metrics_password`), so the metrics endpoint stays reviewable while the credential lives in vault. The committed credential is treated as compromised; removal from HEAD is sufficient scope here (history rewrite is out of scope, rotation makes history moot).
3. **`entrypoints` lives in playbook vars, per cluster.** Official testnet entrypoints (`entrypoint.testnet.solana.com:8001`, `entrypoint2...`, `entrypoint3...`) defined next to `known_validators`, which already follows the per-cluster pattern; asserted in `pre_tasks` with `entrypoints is defined and entrypoints | length > 0`. Alternative — role defaults keyed by cluster — rejected: hides cluster data in role internals and duplicates across validator/rpc.
4. **Arity fix passes an explicit empty tags dict.** The three broken scripts become `measurement_from_fields("<name>", info, {}, config)`. The working caller (`measurement_validator_info.py:341`) passes a populated tags dict; these cluster-wide scripts have no per-validator identity to tag, and `measurement_from_fields` already stamps `cluster_environment` on both fields and the measurement. No behavioral guesswork beyond restoring the intended call.
5. **Fixed scripts stay uploaded even though their only invoker (`telegraf.rpc.conf.j2`) is deleted.** They are generic InfluxDB output utilities runnable via `output_starter.sh`; deleting the orphaned RPC telegraf path removes the 2019 Telegraf pin and plaintext TimescaleDB creds without destroying working utilities. If a future RPC monitoring story lands, they're ready.
6. **Deletions over quarantine.** Per user decision: `ansible_user.yaml`, the telegraf_rpc pair, `validator_monitoring.py`, and the three `tds_*` files are deleted outright; git history preserves them.
7. **Verification is static.** `ansible-playbook` is never run locally; the change is verified with `python3 -m py_compile` / import smoke tests on the monitoring files, `grep` audits for secrets and orphan references, and Jinja-level review of the template loop. CI-based syntax checking arrives with `add-ci-guardrails`.

## Risks / Trade-offs

- [Vault password becomes a new operational dependency] → `secrets.example.yaml` documents setup; README section explains `--ask-vault-pass` / `--vault-password-file`; assertion failures name the missing vars if the vault isn't loaded.
- [The exposed credential remains in git history] → Rotation (operator action, called out in tasks) makes the historical value worthless; no history rewrite attempted.
- [`entrypoints` values could go stale as Anza changes DNS] → They are data in the playbook, not logic; trivially updatable, and the assertion guarantees loud failure rather than silent template errors.
- [Passing `{}` tags changes emitted measurement shape vs. some historical intent] → The scripts currently cannot run at all; any output is an improvement, and the tags slot previously received the config object (garbage).
- [Deleting telegraf_rpc removes the only (broken) RPC monitoring path] → Documented as an explicit gap; a future change can build a modern one (noted as follow-up, not blocked).

## Migration Plan

1. Land vault files + playbook edits + deletions + Python fixes in one commit on a branch.
2. Operator rotates the metrics write credential and creates `vault/secrets.yaml` locally (`ansible-vault encrypt`).
3. Next real playbook run requires `--vault-password-file`; no host-side migration — executed task set is unchanged.
4. Rollback: revert the commit; the old playbook still works (secrets were inline).

## Open Questions

- None blocking. Follow-up candidate: a modern RPC-node monitoring change to replace the deleted telegraf_rpc path.
