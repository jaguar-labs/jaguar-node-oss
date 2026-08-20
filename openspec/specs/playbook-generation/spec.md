# playbook-generation Specification

## Purpose
TBD - created by syncing change `add-playbook-wizard`. Defines the interactive wizard that generates validator playbooks from the committed template, prompting only for validator-specific essentials and filling cluster presets automatically.

## Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet`, `mainnet`, or `alpenglow`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), the disk configuration (via the selection-first assignment flow when unused disks are detected, else the classic layout prompt: `separate` or `single`, default `separate`, with the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region) — skipped and rendered disabled on `alpenglow`, which has no Jito — alpenglow's restart-sensitive values (`expected_shred_version`, `expected_bank_hash`, defaults from the presets with a check-latest warning) when that cluster is chosen, and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk paths with the sample profile's defaults and feature toggles (Jito on for testnet/mainnet, XDP off), plus the disk-setup script for the default devices

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet/alpenglow, a pubkey that is neither 32-44 base58 characters nor the deferral token, disk layout other than separate/single)
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

### Requirement: Single-disk layout generation
When all three roles land on one device (classic `single` layout or an all-on-one assignment), the generated playbook SHALL contain path variables `ledger_path: /mnt/solana/ledger`, `accounts_path: /mnt/solana/accounts`, `snapshots_path: /mnt/solana/snapshots` — and nothing else disk-related: generated playbooks SHALL NOT contain a `disk_management` structure. Utility script templates SHALL derive their paths from `snapshots_path`/`ledger_path` so they are correct in every layout.

#### Scenario: Single-disk generation
- **WHEN** the operator puts everything on one device
- **THEN** the playbook's three path vars point under `/mnt/solana/`, no `disk_management` block exists, and the disk-setup script formats and mounts that one device at `/mnt/solana`

#### Scenario: Utility scripts follow the layout
- **WHEN** a single-disk playbook is deployed
- **THEN** the rendered `dl-snapshots.sh` default output dir equals the playbook's `snapshots_path` and `node-transition.sh`'s tower-file check uses the playbook's `ledger_path`, with no hardcoded `/mnt/solana_*` mount assumptions

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
Every wizard run that configures disks SHALL print the disk preparation commands — `mkfs.xfs` per device, `mount` using the repo's tuned mount options, a UUID-based `/etc/fstab` entry, and `mount -a` verification — filled in with the operator's actual devices and mount dirs, and SHALL write the same commands to `playbooks/disk-setup-<name>.sh` (gitignored). The script SHALL refuse to execute without an explicit `--yes` flag and SHALL print its own contents when run without it. The wizard's next-steps SHALL state that the script must be run on the target host as root before the playbook.

#### Scenario: Commands match the playbook
- **WHEN** the wizard completes
- **THEN** the printed/saved commands reference exactly the devices and mount dirs behind the playbook's path variables, with the repo's mount options string

#### Scenario: Destructive-command guard
- **WHEN** the operator runs `disk-setup-<name>.sh` without `--yes`
- **THEN** the script prints the commands it would run and exits non-zero without executing any of them
