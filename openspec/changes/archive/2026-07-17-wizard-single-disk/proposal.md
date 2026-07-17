# Proposal: wizard-single-disk

## Why

The wizard currently assumes three dedicated NVMe devices (ledger, accounts, snapshots), but plenty of validator hosts — especially testnet and smaller bare-metal configurations — have a single large NVMe. Operators on such hosts must hand-edit the generated playbook's `disk_management` block and the three path variables, which is exactly the error-prone editing the wizard exists to remove.

## What Changes

- Add a **disk layout** prompt to `bin/new-playbook.sh`: `separate` (current behavior, default) or `single`.
  - `single` asks for one device (default `/dev/nvme0n1`) and generates a `disk_management` block whose three entries share that device and mount dir `/mnt/solana`, with subdirs `ledger`/`accounts`/`snapshots` — the existing `disks_mount.yaml` role logic handles this with zero role changes (repeat format/mount iterations are idempotent no-ops).
  - Path variables follow the layout: `ledger_path`/`accounts_path`/`snapshots_path` point under `/mnt/solana/` in single mode, under the three `/mnt/solana_*` mounts in separate mode.
- Template changes in `playbooks/templates/profile.yaml.tmpl`: the fixed three-disk block becomes a `@@DISK_MANAGEMENT_DISKS@@` block token; the three path vars become `@@LEDGER_PATH@@`/`@@ACCOUNTS_PATH@@`/`@@SNAPSHOTS_PATH@@` tokens.
- Consistency fixes so single-disk hosts get working utility scripts (currently hardcoded to the separate-disk mounts):
  - `roles/validator/templates/dl-snapshots.sh.j2`: `DEFAULT_OUTPUT_DIR` uses `{{ snapshots_path }}` instead of `/mnt/solana_snapshots/snapshots`.
  - `roles/validator/templates/node-transition.sh.j2` line 36: tower-file check uses `{{ ledger_path }}` instead of `/mnt/solana_ledger/ledger`.
- Regenerate `sample-testnet-profile.yaml` (separate layout) to prove the refactored template round-trips unchanged.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `playbook-generation`: the essential-prompts requirement gains the disk layout question, and a new requirement covers single-disk generation semantics (shared device entries, path derivation, role-idempotency assumption).

## Impact

- `bin/new-playbook.sh` — new prompt, two disk-block renderers, path derivation.
- `playbooks/templates/profile.yaml.tmpl` — disk block and path tokenization.
- `roles/validator/templates/dl-snapshots.sh.j2`, `node-transition.sh.j2` — path templating fixes (affect all hosts, but values are unchanged for existing separate-disk deployments).
- `playbooks/sample-testnet-profile.yaml` — regenerated (expected identical).
- No role task changes; no new host behavior for existing separate-disk playbooks.
