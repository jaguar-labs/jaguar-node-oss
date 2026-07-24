# playbook-generation Specification

## Purpose
TBD - created by syncing change `add-playbook-wizard`. Defines the interactive wizard that generates validator playbooks from the committed template, prompting only for validator-specific essentials and filling cluster presets automatically.

## Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), disk layout (`separate`, `single`, or `manual`, default `separate`), the disk shape and device(s) for the chosen layout (three devices for `separate`, one for `single`; `manual` first asks which of those two shapes the operator prepared, then the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk layout with the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, a pubkey that is neither 32-44 base58 characters nor the deferral token, disk layout other than separate/single/manual)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

#### Scenario: Deferred keys accepted
- **WHEN** the operator answers `gen` at the identity prompt and `skip` at the vote account prompt
- **THEN** the playbook is generated with both pubkey vars empty, and the next-steps output explains that the host generates both keypairs during provisioning and prints the on-chain `solana create-vote-account` command the operator must run afterwards

### Requirement: Cluster choice supplies correct presets
Selecting a cluster SHALL auto-fill, without prompting: gossip entrypoints, known validators, expected genesis hash, remote cluster RPC address, solana metrics database parameters, and — when Jito is enabled — the cluster-appropriate block-engine URL, shred receiver address, tip payment/distribution program pubkeys, merkle root upload authority, and Jito NTP server.

#### Scenario: Testnet presets
- **WHEN** the operator selects `testnet`
- **THEN** the generated playbook contains the testnet entrypoints (`entrypoint*.testnet.solana.com:8001`), testnet genesis hash `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY`, and testnet Jito endpoints if Jito is enabled

#### Scenario: Mainnet presets
- **WHEN** the operator selects `mainnet`
- **THEN** the generated playbook contains mainnet entrypoints, the mainnet genesis hash `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d`, mainnet known validators, and mainnet Jito endpoints if Jito is enabled

### Requirement: Generation is template-based and overwrite-safe
The playbook SHALL be produced by substituting `@@TOKEN@@` placeholders in the committed template `playbooks/templates/profile.yaml.tmpl`, written to `playbooks/<validator-name>-<cluster>-profile.yaml`. If the target file exists, the wizard SHALL abort with a message unless `--force` is passed. After substitution the wizard SHALL verify no `@@` placeholder remains in the output.

#### Scenario: Target exists without --force
- **WHEN** the wizard would write a playbook path that already exists and `--force` was not given
- **THEN** it exits non-zero without modifying the file, telling the operator to re-run with `--force` to overwrite

#### Scenario: Unsubstituted placeholder detection
- **WHEN** substitution completes but a `@@TOKEN@@` remains (e.g. template gained a new token the wizard does not know)
- **THEN** the wizard deletes the partial output and exits non-zero naming the unfilled token

### Requirement: Generated playbooks satisfy the playbook variable contract
Generated output SHALL parse as valid YAML and define every variable required by the `playbook-variable-contract` spec, including a non-empty `entrypoints` list, and SHALL load secrets via `vars_files: ../vault/secrets.yaml` exactly as the sample profile does.

#### Scenario: Generated playbook passes CI
- **WHEN** a generated playbook is committed and CI runs
- **THEN** yamllint and `ansible-playbook --syntax-check` (with the dummy vault) pass without modification

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

### Requirement: Manual disk mode generation
When the operator chooses the `manual` layout, the generated playbook SHALL set `disk_management.mount: False` and `disk_management.config: True` — the role neither formats nor mounts, but still creates the `ledger`/`accounts`/`snapshots` subdirs with `{{ solana_user }}` ownership on the operator-prepared mount(s). The `disks` entries, mount dirs, and path variables SHALL be identical to the corresponding automated layout (`separate` or `single`), so switching a playbook between manual and automated modes changes only the two flags. In the automated layouts both flags SHALL render `True`, keeping their generated output byte-identical to before this change.

#### Scenario: Manual single-disk generation
- **WHEN** the operator selects `manual`, shape `single`, and a device
- **THEN** the playbook's `disk_management` has `mount: False, config: True`, three entries sharing `/mnt/solana` + the device, and paths under `/mnt/solana/` — differing from the automated `single` output only in the two flags

#### Scenario: Automated layouts unchanged
- **WHEN** the operator selects `separate` or `single` with default inputs
- **THEN** the generated playbook is byte-identical to the pre-change wizard output, and regenerating the sample yields an empty diff

### Requirement: Manual mode delivers the exact setup commands
In `manual` mode the wizard SHALL print the disk preparation commands — `mkfs.xfs` per device, `mount` using the repo's tuned mount options, a UUID-based `/etc/fstab` entry, and `mount -a` verification — filled in with the operator's actual devices and mount dirs, and SHALL write the same commands to `playbooks/disk-setup-<name>.sh`. The script SHALL refuse to execute without an explicit `--yes` flag (it contains destructive `mkfs` commands) and SHALL print its own contents when run without it. The script path SHALL be gitignored.

#### Scenario: Commands match the playbook
- **WHEN** the wizard completes in manual mode
- **THEN** the printed/saved commands reference exactly the devices and mount dirs present in the generated playbook's `disks` entries, with the same mount options string the automated mode would have used

#### Scenario: Destructive-command guard
- **WHEN** the operator runs `disk-setup-<name>.sh` without `--yes`
- **THEN** the script prints the commands it would run and exits non-zero without executing any of them

### Requirement: Device prompts propose detected unused disks
Before the disk configuration prompts, the wizard SHALL detect unused disks on the machine it runs on — block devices of type `disk` with no partitions, no filesystem signature, and nothing mounted — and list them numbered with sizes. When one or more are detected, the wizard SHALL enter the selection-first assignment flow (see "Interactive disk assignment"); answering `none` there, or when no disks are detected (or `lsblk` is unavailable), the wizard SHALL fall back to the classic layout prompt with detected disks (in order) as the device prompt defaults and static defaults beyond that. The listing SHALL note that detection reflects the wizard's machine and should be ignored when preparing a playbook for a different host.

#### Scenario: Unused disks present
- **WHEN** the wizard runs on a host with bare NVMe devices (no partitions, no filesystem, unmounted)
- **THEN** those devices are listed numbered with their sizes and the selection prompt is shown

#### Scenario: Assignment declined
- **WHEN** unused disks are detected but the operator answers `none` at the selection prompt
- **THEN** the classic layout prompt runs with the detected disks pre-filled as device defaults, in detection order

#### Scenario: No unused disks
- **WHEN** the wizard runs on a machine whose disks are all partitioned, formatted, or mounted
- **THEN** no detection listing or selection prompt is shown and the classic prompts default to the static values (`/dev/nvme0n1`, `/dev/nvme1n1`, `/dev/nvme4n1`)

### Requirement: Interactive disk assignment
The assignment flow SHALL be selection-first. The detected disks are listed numbered, and one prompt asks which to select: numbers or device paths (comma-separated), `all` (default), or `none` to fall back to the classic layout prompts. The selection SHALL be validated (known disks only, deduplicated, 1–3 disks — three roles cannot spread further) and re-prompted on invalid input. Each selected disk then gets a role prompt — `ledger`, `accounts`, `snapshots` (one or more, comma-separated) or `all` — with defaults by selection count (one disk → `all`; two → `ledger` and `accounts,snapshots`; three → one role each). The wizard SHALL validate that each of the three roles is assigned exactly once across the selected disks — re-prompting on duplicate roles or unknown values. The last selected disk's prompt SHALL default to exactly the still-unassigned roles and SHALL reject any answer that does not cover them (naming the missing roles), so under-assignment is corrected at the prompt where it happens instead of looping; a full role-prompt restart (keeping the selection) remains only as a safety net. The wizard SHALL then ask whether the playbook formats and mounts the disks (automated) or the operator prepares them (manual semantics: `disk_management.mount: False, config: True` plus the generated `disk-setup-<name>.sh` covering exactly the assigned disks).

#### Scenario: Select-then-assign
- **WHEN** three disks are detected, the operator selects `1,3`, and assigns `ledger` and `accounts,snapshots`
- **THEN** the generated playbook maps ledger to the first selected disk and accounts+snapshots to the second, with the unselected disk untouched

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
The disks block, mount dirs, and path variables SHALL be derived from the assignment map: each used disk gets one mount dir — `/mnt/solana` when it carries all three roles, `/mnt/solana_<role>` for a single role, `/mnt/solana_` + the roles joined with `_` (in ledger/accounts/snapshots order) for a shared disk — and the disks list contains one entry per role (with its `subdir`/`startup_arg`) pointing at its disk's mount dir, sharing entries idempotently exactly as the single-disk layout does. Path variables point at `<mount_dir>/<role>`. Generated playbooks SHALL satisfy the playbook variable contract and pass CI unchanged.

#### Scenario: Hybrid two-disk mapping
- **WHEN** disk A is assigned `ledger` and disk B is assigned `accounts,snapshots`
- **THEN** the playbook mounts A at `/mnt/solana_ledger` (one entry) and B at `/mnt/solana_accounts_snapshots` (two shared entries with distinct subdirs), with `ledger_path: /mnt/solana_ledger/ledger`, `accounts_path: /mnt/solana_accounts_snapshots/accounts`, `snapshots_path: /mnt/solana_accounts_snapshots/snapshots`

#### Scenario: Assignment equals a classic layout
- **WHEN** the assignment maps to exactly the `separate` or `single` shape
- **THEN** the generated disks block and paths are byte-identical to that classic layout's output

### Requirement: XDP interface prompt is bond-aware
When XDP is enabled, the wizard SHALL detect bonded interfaces on the machine it runs on (via `/sys/class/net/bonding_masters`), display each bond with its members and active member, and propose a physical member (the active member when set, else the first) as the interface prompt default. The prompt SHALL reject a bond master name — entering one re-prompts with the bond's member list — because XDP and NIC ring tuning require a physical NIC. With no bonds present, the prompt behaves as before (no default).

#### Scenario: Bonded host proposes a member
- **WHEN** the wizard runs on a host with `bond0` over `enp67s0f0`/`enp67s0f1` and XDP is enabled
- **THEN** the bond and its members are displayed and the interface prompt defaults to a physical member, never `bond0`

#### Scenario: Bond master rejected
- **WHEN** the operator types a bond master name (e.g. `bond0`) at the interface prompt
- **THEN** the wizard re-prompts, listing the bond's members to choose from

#### Scenario: No bond present
- **WHEN** the machine has no bonded interfaces
- **THEN** no bond listing is shown and the interface prompt has no pre-filled default
