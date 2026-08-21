# playbook-generation Specification

## Purpose
TBD - created by syncing change `add-playbook-wizard`. Defines the interactive wizard that generates validator playbooks from the committed template, prompting only for validator-specific essentials and filling cluster presets automatically.

## Requirements

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

### Requirement: Cluster choice supplies correct presets
Selecting a cluster SHALL auto-fill, without prompting: gossip entrypoints, known validators (empty for `alpenglow`), expected genesis hash, remote cluster RPC address, solana metrics database parameters, the dynamic port range (`8000-10000` for testnet/mainnet, `9000-12500` for alpenglow), the agave version (`solana_version`: `4.1.0-beta.3` for testnet/mainnet, `4.2.0-beta.0` for alpenglow), and — when Jito is enabled — the cluster-appropriate block-engine URL, shred receiver address, tip payment/distribution program pubkeys, merkle root upload authority, and Jito NTP server.

#### Scenario: Testnet presets
- **WHEN** the operator selects `testnet`
- **THEN** the generated playbook contains the testnet entrypoints (`entrypoint*.testnet.solana.com:8001`), testnet genesis hash `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY`, and testnet Jito endpoints if Jito is enabled

#### Scenario: Mainnet presets
- **WHEN** the operator selects `mainnet`
- **THEN** the generated playbook contains mainnet entrypoints, the mainnet genesis hash `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d`, mainnet known validators, and mainnet Jito endpoints if Jito is enabled

#### Scenario: Alpenglow presets
- **WHEN** the operator selects `alpenglow`
- **THEN** the generated playbook contains the alpenglow IP entrypoints (`64.130.37.11:8000`, `213.239.141.16:8001`), genesis hash `HtRW7y9hJZaEBgH8cvUomQQjaXY5vM8J54nqbZJz7MjW`, remote RPC `http://185.8.106.234:8899`, metrics `db=alpenglow-testnet` with the public `ag` credentials, `dynamic_port_range: 9000-12500`, an empty known-validators list, and `jito.enabled: False`

#### Scenario: Existing clusters unchanged
- **WHEN** a testnet or mainnet playbook is regenerated with pre-change inputs
- **THEN** the output is byte-identical (the port-range token renders the previous constant)

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

### Requirement: Device prompts propose detected unused disks
Before the storage placement prompts, the wizard SHALL detect unused disks on the machine it runs on — block devices of type `disk` with no partitions, no filesystem signature, and nothing mounted — and list them numbered with sizes. Detected disks populate the `unused disk` pickers of the role-first placement flow; a disk already placed for one role SHALL NOT be offered again for another (one disk, one mount — sharing is expressed via `existing location` under the first role's mount). When no disks are detected (or `lsblk` is unavailable), the `unused disk` option SHALL be absent and each role is placed by location only. The listing SHALL note that detection reflects the wizard's machine and should be ignored when preparing a playbook for a different host.

#### Scenario: Unused disks present
- **WHEN** the wizard runs on a host with bare NVMe devices
- **THEN** those devices appear (with sizes) in the ledger placement picker, and a device chosen for ledger no longer appears in the snapshots or accounts pickers

#### Scenario: Assignment declined
- **WHEN** unused disks are detected but the operator places every role on an `existing location`
- **THEN** no detected disk is touched and no disk-setup script is produced — declining disk use is per role, not a separate mode

#### Scenario: No unused disks
- **WHEN** the wizard runs on a machine whose disks are all partitioned, formatted, or mounted
- **THEN** no detection listing is shown and each role's placement offers only `existing location` (plus `with ledger` for snapshots), defaulting to the standard paths

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

### Requirement: Disk preparation commands always generated
When at least one role is placed on an unused disk, the wizard SHALL print the disk preparation commands — `mkfs.xfs` per placed device, `mount` at the chosen location's mount dir using the repo's tuned mount options, a UUID-based `/etc/fstab` entry, and `mount -a` verification — and SHALL write the same commands to `playbooks/disk-setup-<name>.sh` (gitignored), covering exactly the placed disks. The script SHALL refuse to execute without an explicit `--yes` flag and SHALL print its own contents when run without it. The wizard's next-steps SHALL state that the script must be run on the target host as root before the playbook. When every role landed on an existing location, no setup script SHALL be produced.

#### Scenario: Commands match the playbook
- **WHEN** ledger is placed on an unused disk at `/mnt/solana_ledger/ledger` and accounts on an existing location
- **THEN** the setup script formats and mounts only the ledger disk at `/mnt/solana_ledger` (the same device and mount dir behind the playbook's `ledger_path`), and the accounts path appears nowhere in it

#### Scenario: Destructive-command guard
- **WHEN** the operator runs `disk-setup-<name>.sh` without `--yes`
- **THEN** the script prints the commands it would run and exits non-zero without executing any of them

#### Scenario: All-existing placement produces no script
- **WHEN** every role is placed on an existing location
- **THEN** no `disk-setup-<name>.sh` is written and next-steps omits the disk-preparation step

### Requirement: Role-first storage placement
The wizard SHALL place storage role by role, in order: **ledger** (menu: `unused disk` / `existing location`; picking a disk then prompts for the location, default `/mnt/solana_ledger/ledger`, and the disk is prepared at the location's parent directory; `existing location` prompts for an absolute path with the same default and prepares nothing), **snapshots** (menu: `with ledger` — the default — / `unused disk` / `existing location`, ceremony as ledger with default `/mnt/solana_snapshots/snapshots`), **accounts** (ceremony as ledger, default `/mnt/solana_accounts/accounts` — accounts are never co-located with ledger: an accounts location resolving under the ledger mount SHALL be rejected with a message and re-prompted). The resulting `ledger_path`/`accounts_path`/`snapshots_path` SHALL feed the playbook exactly as before (locations only; Ansible never touches block devices).

#### Scenario: Mixed placement
- **WHEN** ledger goes to an unused disk (default location), snapshots `with ledger`, and accounts to an existing location `/data/accounts`
- **THEN** the playbook has `ledger_path: /mnt/solana_ledger/ledger`, `snapshots_path` equal to `ledger_path`, `accounts_path: /data/accounts`, and the setup script prepares only the ledger disk

#### Scenario: Defaults reproduce the separate layout
- **WHEN** the operator accepts every placement default on a host with three unused disks
- **THEN** ledger/accounts land on distinct disks at the standard paths, snapshots ride with ledger, and the setup script covers the two placed disks

#### Scenario: Accounts co-location rejected
- **WHEN** the operator enters an accounts location under the ledger mount (e.g. `/mnt/solana_ledger/accounts`)
- **THEN** the wizard rejects it, stating that accounts always live on their own disk/mount, and re-prompts

### Requirement: Fixed-choice prompts are arrow-key menus with a non-tty fallback
All fixed-choice prompts — cluster selection, every yes/no toggle (Jito, XDP, vault creation), the Jito region, and the storage placement menus and disk pickers — SHALL render as interactive menus navigated with the Up/Down arrow keys and confirmed with Enter (the default option pre-highlighted), implemented via a reusable helper reading terminal escape sequences. When the wizard's input is not a terminal (piped/scripted use), the same prompts SHALL fall back to a numbered plain-text listing accepting the option number or its label — including the legacy labels (`y`/`n`, cluster names, region names) — so scripted end-to-end runs stay deterministic and existing input sequences keep working.

#### Scenario: Interactive selection
- **WHEN** the operator runs the wizard on a terminal and presses Down then Enter at the ledger placement menu
- **THEN** the second option is selected without typing its name

#### Scenario: Scripted selection
- **WHEN** the wizard runs with piped stdin
- **THEN** menus print numbered options and consume one input line each, and legacy answers (`y`, `n`, `testnet`, region names) select the matching option

#### Scenario: Whole flow is menu-driven
- **WHEN** the operator runs the wizard on a terminal
- **THEN** cluster, Jito/XDP/vault toggles, Jito region, and all storage choices are arrow-key menus — no fixed-choice prompt requires typing its answer

### Requirement: Snapshots co-located with ledger omit the startup argument
When snapshots are placed `with ledger`, the generated `snapshots_path` SHALL equal `ledger_path` and every start-script template SHALL omit the `--snapshots` argument (agave's default snapshot location is the ledger directory; per the minimal-flags convention an argument equal to the default must not appear). When snapshots have their own location, `--snapshots {{ snapshots_path }}` SHALL be emitted as before.

#### Scenario: Co-located snapshots
- **WHEN** a playbook generated with snapshots `with ledger` renders any start script variant
- **THEN** the script contains no `--snapshots` argument, and `dl-snapshots.sh`/directory creation use the ledger directory

#### Scenario: Dedicated snapshots
- **WHEN** `snapshots_path` differs from `ledger_path`
- **THEN** the rendered start script contains `--snapshots {{ snapshots_path }}`
