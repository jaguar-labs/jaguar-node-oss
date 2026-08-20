## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet`, `mainnet`, or `alpenglow`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), the storage placement (role-first: ledger, then snapshots, then accounts — see "Role-first storage placement"), validator log path, Jito enabled (and if yes: commission bps and block-engine region) — skipped and rendered disabled on `alpenglow`, which has no Jito — alpenglow's restart-sensitive values (`expected_shred_version`, `expected_bank_hash`, defaults from the presets with a check-latest warning) when that cluster is chosen, and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated with the default per-role locations (`/mnt/solana_ledger/ledger`, snapshots with ledger, `/mnt/solana_accounts/accounts`) and feature toggles (Jito on for testnet/mainnet, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet/alpenglow, a pubkey that is neither 32-44 base58 characters nor the deferral token, a non-absolute storage location)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

#### Scenario: Deferred keys accepted
- **WHEN** the operator answers `gen` at the identity prompt and `skip` at the vote account prompt
- **THEN** the playbook is generated with both pubkey vars empty, and the next-steps output explains that the host generates both keypairs during provisioning and prints the on-chain `solana create-vote-account` command the operator must run afterwards

#### Scenario: Alpenglow skips Jito
- **WHEN** the operator selects `alpenglow`
- **THEN** no Jito prompts appear, the generated playbook has `jito.enabled: False`, and the shred-version/bank-hash prompts appear with preset defaults and a warning that they change on cluster restarts

### Requirement: Device prompts propose detected unused disks
Before the storage placement prompts, the wizard SHALL detect unused disks on the machine it runs on — block devices of type `disk` with no partitions, no filesystem signature, and nothing mounted — and list them numbered with sizes. Detected disks populate the `unused disk` pickers of the role-first placement flow; a disk already placed for one role SHALL NOT be offered again for another (one disk, one mount — sharing is expressed via `existing location` under the first role's mount). When no disks are detected (or `lsblk` is unavailable), the `unused disk` option SHALL be absent and each role is placed by location only. The listing SHALL note that detection reflects the wizard's machine and should be ignored when preparing a playbook for a different host.

#### Scenario: Unused disks feed the pickers
- **WHEN** the wizard runs on a host with bare NVMe devices
- **THEN** those devices appear (with sizes) in the ledger placement picker, and a device chosen for ledger no longer appears in the snapshots or accounts pickers

#### Scenario: No unused disks
- **WHEN** the wizard runs on a machine whose disks are all partitioned, formatted, or mounted
- **THEN** no detection listing is shown and each role's placement offers only `existing location` (plus `with ledger` for snapshots), defaulting to the standard paths

### Requirement: Disk preparation commands always generated
When at least one role is placed on an unused disk, the wizard SHALL print the disk preparation commands — `mkfs.xfs` per placed device, `mount` at the chosen location's mount dir using the repo's tuned mount options, a UUID-based `/etc/fstab` entry, and `mount -a` verification — and SHALL write the same commands to `playbooks/disk-setup-<name>.sh` (gitignored), covering exactly the placed disks. The script SHALL refuse to execute without an explicit `--yes` flag and SHALL print its own contents when run without it. The wizard's next-steps SHALL state that the script must be run on the target host as root before the playbook. When every role landed on an existing location, no setup script SHALL be produced.

#### Scenario: Commands match the placements
- **WHEN** ledger is placed on an unused disk at `/mnt/solana_ledger/ledger` and accounts on an existing location
- **THEN** the setup script formats and mounts only the ledger disk at `/mnt/solana_ledger`, and the accounts path appears nowhere in it

#### Scenario: Destructive-command guard
- **WHEN** the operator runs `disk-setup-<name>.sh` without `--yes`
- **THEN** the script prints the commands it would run and exits non-zero without executing any of them

#### Scenario: All-existing placement produces no script
- **WHEN** every role is placed on an existing location
- **THEN** no `disk-setup-<name>.sh` is written and next-steps omits the disk-preparation step

## REMOVED Requirements

### Requirement: Interactive disk assignment
**Reason**: Superseded by role-first placement — operators answer per-role questions instead of selecting disks and distributing roles over them.
**Migration**: None; the same placements (and more, e.g. existing filesystems) are expressible in the new flow.

### Requirement: Assignment-derived hybrid layouts
**Reason**: Mount dirs are no longer derived from a role→disk map; each role's location is operator-chosen (with role defaults), so hybrid layouts are just placements whose locations share a mount.
**Migration**: Existing generated playbooks are unaffected; regenerate through the new flow to change layouts.

### Requirement: Single-disk layout generation
**Reason**: Superseded — an all-on-one host is expressed as ledger on the disk, snapshots `with ledger`, accounts at an `existing location` under the same mount.
**Migration**: Existing single-layout playbooks keep working (paths-only contract unchanged).

## ADDED Requirements

### Requirement: Role-first storage placement
The wizard SHALL place storage role by role, in order: **ledger** (menu: `unused disk` / `existing location`; picking a disk then prompts for the location, default `/mnt/solana_ledger/ledger`, and the disk is prepared at the location's parent directory; `existing location` prompts for an absolute path with the same default and prepares nothing), **snapshots** (menu: `with ledger` — the default — / `unused disk` / `existing location`, ceremony as ledger with default `/mnt/solana_snapshots/snapshots`), **accounts** (ceremony as ledger, default `/mnt/solana_accounts/accounts`). The resulting `ledger_path`/`accounts_path`/`snapshots_path` SHALL feed the playbook exactly as before (locations only; Ansible never touches block devices).

#### Scenario: Mixed placement
- **WHEN** ledger goes to an unused disk (default location), snapshots `with ledger`, and accounts to an existing location `/data/accounts`
- **THEN** the playbook has `ledger_path: /mnt/solana_ledger/ledger`, `snapshots_path` equal to `ledger_path`, `accounts_path: /data/accounts`, and the setup script prepares only the ledger disk

#### Scenario: Defaults reproduce the separate layout
- **WHEN** the operator accepts every placement default on a host with three unused disks
- **THEN** ledger/accounts land on distinct disks at the standard paths, snapshots ride with ledger, and the setup script covers the two placed disks

### Requirement: Fixed-choice prompts are arrow-key menus with a non-tty fallback
Fixed-choice storage prompts SHALL render as interactive menus navigated with the Up/Down arrow keys and confirmed with Enter (the default option pre-highlighted), implemented via a reusable helper reading terminal escape sequences. When the wizard's input is not a terminal (piped/scripted use), the same prompts SHALL fall back to a numbered plain-text listing accepting the option number (or its label), preserving scripted end-to-end runs byte-for-byte deterministically.

#### Scenario: Interactive selection
- **WHEN** the operator runs the wizard on a terminal and presses Down then Enter at the ledger placement menu
- **THEN** the second option is selected without typing its name

#### Scenario: Scripted selection
- **WHEN** the wizard runs with piped stdin
- **THEN** menus print numbered options and consume one input line each, and the existing e2e input-sequence style keeps working

### Requirement: Snapshots co-located with ledger omit the startup argument
When snapshots are placed `with ledger`, the generated `snapshots_path` SHALL equal `ledger_path` and every start-script template SHALL omit the `--snapshots` argument (agave's default snapshot location is the ledger directory; per the minimal-flags convention an argument equal to the default must not appear). When snapshots have their own location, `--snapshots {{ snapshots_path }}` SHALL be emitted as before.

#### Scenario: Co-located snapshots
- **WHEN** a playbook generated with snapshots `with ledger` renders any start script variant
- **THEN** the script contains no `--snapshots` argument, and `dl-snapshots.sh`/directory creation use the ledger directory

#### Scenario: Dedicated snapshots
- **WHEN** `snapshots_path` differs from `ledger_path`
- **THEN** the rendered start script contains `--snapshots {{ snapshots_path }}`
