## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey, vote account pubkey, disk layout (`separate`, `single`, or `manual`, default `separate`), the disk shape and device(s) for the chosen layout (three devices for `separate`, one for `single`; `manual` first asks which of those two shapes the operator prepared, then the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk layout with the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, pubkey that is not 32-44 base58 characters, disk layout other than separate/single/manual)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

## ADDED Requirements

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
