## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), the disk configuration (via the selection-first assignment flow when unused disks are detected, else the classic layout prompt: `separate` or `single`, default `separate`, with the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk paths with the sample profile's defaults and feature toggles (Jito on, XDP off), plus the disk-setup script for the default devices

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, a pubkey that is neither 32-44 base58 characters nor the deferral token, disk layout other than separate/single)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

#### Scenario: Deferred keys accepted
- **WHEN** the operator answers `gen` at the identity prompt and `skip` at the vote account prompt
- **THEN** the playbook is generated with both pubkey vars empty, and the next-steps output explains that the host generates both keypairs during provisioning and prints the on-chain `solana create-vote-account` command the operator must run afterwards

### Requirement: Single-disk layout generation
When all three roles land on one device (classic `single` layout or an all-on-one assignment), the generated playbook SHALL contain path variables `ledger_path: /mnt/solana/ledger`, `accounts_path: /mnt/solana/accounts`, `snapshots_path: /mnt/solana/snapshots` — and nothing else disk-related: generated playbooks SHALL NOT contain a `disk_management` structure. Utility script templates SHALL derive their paths from `snapshots_path`/`ledger_path` so they are correct in every layout.

#### Scenario: Single-disk generation
- **WHEN** the operator puts everything on one device
- **THEN** the playbook's three path vars point under `/mnt/solana/`, no `disk_management` block exists, and the disk-setup script formats and mounts that one device at `/mnt/solana`

#### Scenario: Utility scripts follow the layout
- **WHEN** a single-disk playbook is deployed
- **THEN** the rendered `dl-snapshots.sh` default output dir equals the playbook's `snapshots_path` and `node-transition.sh`'s tower-file check uses the playbook's `ledger_path`, with no hardcoded `/mnt/solana_*` mount assumptions

### Requirement: Interactive disk assignment
The assignment flow SHALL be selection-first. The detected disks are listed numbered, and one prompt asks which to select: numbers or device paths (comma-separated), `all` (default), or `none` to fall back to the classic layout prompts. The selection SHALL be validated (known disks only, deduplicated, 1–3 disks — three roles cannot spread further) and re-prompted on invalid input. Each selected disk then gets a role prompt — `ledger`, `accounts`, `snapshots` (one or more, comma-separated) or `all` — with defaults by selection count (one disk → `all`; two → `ledger` and `accounts,snapshots`; three → one role each). The wizard SHALL validate that each of the three roles is assigned exactly once across the selected disks — re-prompting on duplicate roles or unknown values. The last selected disk's prompt SHALL default to exactly the still-unassigned roles and SHALL reject any answer that does not cover them (naming the missing roles), so under-assignment is corrected at the prompt where it happens instead of looping; a full role-prompt restart (keeping the selection) remains only as a safety net. The wizard SHALL then always generate the `disk-setup-<name>.sh` script covering exactly the assigned disks — there is no playbook-side disk handling to choose.

#### Scenario: Select-then-assign
- **WHEN** three disks are detected, the operator selects `1,3`, and assigns `ledger` and `accounts,snapshots`
- **THEN** the generated playbook's paths map ledger to the first selected disk's mount dir and accounts+snapshots to the second's, with the unselected disk untouched

#### Scenario: None escapes to classic flow
- **WHEN** the operator answers `none` (or selects nothing) at the selection prompt
- **THEN** the wizard proceeds with the classic layout prompts — no assignment loop, no way to get stuck

#### Scenario: Duplicate role rejected
- **WHEN** the operator assigns `ledger` to a second selected disk
- **THEN** the wizard re-prompts for that disk, naming the disk that already carries `ledger`

#### Scenario: Last disk must cover the remaining roles
- **WHEN** one disk is selected and the operator answers only `ledger`
- **THEN** the wizard rejects the answer immediately, naming `accounts` and `snapshots` as roles that still need a disk, and re-prompts the same disk (whose default is the remaining role set)

### Requirement: Assignment-derived hybrid layouts
Mount dirs and path variables SHALL be derived from the assignment map: each used disk gets one mount dir — `/mnt/solana` when it carries all three roles, `/mnt/solana_<role>` for a single role, `/mnt/solana_` + the roles joined with `_` (in ledger/accounts/snapshots order) for a shared disk — and path variables point at `<mount_dir>/<role>`. The disk-setup script SHALL prepare exactly the assigned devices at those mount dirs. Generated playbooks SHALL satisfy the playbook variable contract and pass CI unchanged.

#### Scenario: Hybrid two-disk mapping
- **WHEN** disk A is assigned `ledger` and disk B is assigned `accounts,snapshots`
- **THEN** the setup script prepares A at `/mnt/solana_ledger` and B at `/mnt/solana_accounts_snapshots`, and the playbook has `ledger_path: /mnt/solana_ledger/ledger`, `accounts_path: /mnt/solana_accounts_snapshots/accounts`, `snapshots_path: /mnt/solana_accounts_snapshots/snapshots`

#### Scenario: Assignment equals a classic layout
- **WHEN** the assignment maps to exactly the `separate` or `single` shape
- **THEN** the generated paths and setup script are byte-identical to that classic layout's output

## REMOVED Requirements

### Requirement: Manual disk mode generation
**Reason**: The manual/automated distinction no longer exists — Ansible never formats or mounts disks, so every layout has what were previously "manual" semantics, minus the `disk_management` flags (which no longer exist either).
**Migration**: Nothing to do. Generated playbooks carry only path variables; disk preparation always happens via the generated setup script before the playbook runs.

### Requirement: Manual mode delivers the exact setup commands
**Reason**: Superseded by "Disk preparation commands always generated" — the setup script is no longer a manual-mode feature but the only disk-preparation mechanism.
**Migration**: The script's content, `--yes` guard, and gitignore status are unchanged; it is simply always produced.

## ADDED Requirements

### Requirement: Disk preparation commands always generated
Every wizard run that configures disks SHALL print the disk preparation commands — `mkfs.xfs` per device, `mount` using the repo's tuned mount options, a UUID-based `/etc/fstab` entry, and `mount -a` verification — filled in with the operator's actual devices and mount dirs, and SHALL write the same commands to `playbooks/disk-setup-<name>.sh` (gitignored). The script SHALL refuse to execute without an explicit `--yes` flag and SHALL print its own contents when run without it. The wizard's next-steps SHALL state that the script must be run on the target host as root before the playbook.

#### Scenario: Commands match the playbook
- **WHEN** the wizard completes
- **THEN** the printed/saved commands reference exactly the devices and mount dirs behind the playbook's path variables, with the repo's mount options string

#### Scenario: Destructive-command guard
- **WHEN** the operator runs `disk-setup-<name>.sh` without `--yes`
- **THEN** the script prints the commands it would run and exits non-zero without executing any of them
