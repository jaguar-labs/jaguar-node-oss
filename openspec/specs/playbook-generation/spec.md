# playbook-generation Specification

## Purpose
TBD - created by syncing change `add-playbook-wizard`. Defines the interactive wizard that generates validator playbooks from the committed template, prompting only for validator-specific essentials and filling cluster presets automatically.

## Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey, vote account pubkey, disk layout (`separate`, `single`, or `manual`, default `separate`), the disk shape and device(s) for the chosen layout (three devices for `separate`, one for `single`; `manual` first asks which of those two shapes the operator prepared, then the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk layout with the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, pubkey that is not 32-44 base58 characters, disk layout other than separate/single/manual)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

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
Before the device prompts, the wizard SHALL detect unused disks on the machine it runs on — block devices of type `disk` with no partitions, no filesystem signature, and nothing mounted — list them with sizes, and use them (in order) as the proposed defaults for the device prompts. When none are detected (or `lsblk` is unavailable), the prompts SHALL fall back to the static defaults. The listing SHALL note that detection reflects the wizard's machine and should be ignored when preparing a playbook for a different host.

#### Scenario: Unused disks present
- **WHEN** the wizard runs on a host with bare NVMe devices (no partitions, no filesystem, unmounted)
- **THEN** those devices are listed with their sizes and pre-filled as the device prompt defaults, in detection order

#### Scenario: No unused disks
- **WHEN** the wizard runs on a machine whose disks are all partitioned, formatted, or mounted
- **THEN** no detection listing is shown and the device prompts default to the static values (`/dev/nvme0n1`, `/dev/nvme1n1`, `/dev/nvme4n1`)

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
