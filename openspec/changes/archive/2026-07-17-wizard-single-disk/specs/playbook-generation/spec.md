## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey, vote account pubkey, disk layout (`separate` or `single`, default `separate`), the disk device(s) for the chosen layout (three devices for `separate`, one for `single`), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk layout with the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, pubkey that is not 32-44 base58 characters, disk layout other than separate/single)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

## ADDED Requirements

### Requirement: Single-disk layout generation
When the operator chooses the `single` disk layout, the wizard SHALL prompt for one device (default `/dev/nvme0n1`) and generate: a `disk_management.disks` list whose three entries share that device and the mount dir `/mnt/solana` while keeping their distinct `subdir`/`startup_arg` values (`ledger`, `accounts`, `snapshots`), and path variables `ledger_path: /mnt/solana/ledger`, `accounts_path: /mnt/solana/accounts`, `snapshots_path: /mnt/solana/snapshots`. In the `separate` layout the generated structure SHALL remain byte-identical to what the wizard produced before this change. Utility script templates SHALL derive their paths from `snapshots_path`/`ledger_path` so they are correct in both layouts.

#### Scenario: Single-disk generation
- **WHEN** the operator selects `single` and accepts the default device
- **THEN** the generated playbook mounts `/dev/nvme0n1` once at `/mnt/solana`, the three subdirs are created under it by the existing role loop (repeat format/mount iterations being idempotent), and all three path vars point under `/mnt/solana/`

#### Scenario: Separate layout unchanged
- **WHEN** the operator selects `separate` (or accepts the default) with default devices
- **THEN** the generated playbook's `disk_management` block and path vars are identical to the pre-change wizard output, and the regenerated sample playbook shows an empty diff

#### Scenario: Utility scripts follow the layout
- **WHEN** a single-disk playbook is deployed
- **THEN** the rendered `dl-snapshots.sh` default output dir equals the playbook's `snapshots_path` and `node-transition.sh`'s tower-file check uses the playbook's `ledger_path`, with no hardcoded `/mnt/solana_*` mount assumptions
