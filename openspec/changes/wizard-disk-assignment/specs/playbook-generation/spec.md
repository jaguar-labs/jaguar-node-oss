## MODIFIED Requirements

### Requirement: Device prompts propose detected unused disks
Before the disk configuration prompts, the wizard SHALL detect unused disks on the machine it runs on — block devices of type `disk` with no partitions, no filesystem signature, and nothing mounted — and list them with sizes. When one or more are detected, the wizard SHALL offer the interactive disk-assignment flow (see "Interactive disk assignment"); if the operator declines, or when none are detected (or `lsblk` is unavailable), the wizard SHALL fall back to the classic layout prompt with detected disks (in order) as the device prompt defaults and static defaults beyond that. The listing SHALL note that detection reflects the wizard's machine and should be ignored when preparing a playbook for a different host.

#### Scenario: Unused disks present
- **WHEN** the wizard runs on a host with bare NVMe devices (no partitions, no filesystem, unmounted)
- **THEN** those devices are listed with their sizes and the wizard offers to configure them via per-disk assignment

#### Scenario: Assignment declined
- **WHEN** unused disks are detected but the operator declines the assignment flow
- **THEN** the classic layout prompt runs with the detected disks pre-filled as device defaults, in detection order

#### Scenario: No unused disks
- **WHEN** the wizard runs on a machine whose disks are all partitioned, formatted, or mounted
- **THEN** no detection listing or assignment offer is shown and the classic prompts default to the static values (`/dev/nvme0n1`, `/dev/nvme1n1`, `/dev/nvme4n1`)

## ADDED Requirements

### Requirement: Interactive disk assignment
In the assignment flow the wizard SHALL iterate the detected disks, prompting for each: `ledger`, `accounts`, `snapshots` (one or more roles, comma-separated), `all` (all three roles), or `skip`. The wizard SHALL validate that, across all disks, each of the three roles is assigned exactly once — re-prompting with a specific message on duplicate roles, unknown values, or (after the last disk) unassigned roles — and SHALL then ask whether the playbook formats and mounts the disks (automated) or the operator prepares them (manual semantics: `disk_management.mount: False, config: True` plus the generated `disk-setup-<name>.sh` covering exactly the assigned disks).

#### Scenario: Three disks, one role each
- **WHEN** three detected disks are assigned `ledger`, `accounts`, `snapshots` respectively
- **THEN** the generated playbook is equivalent to the classic `separate` layout with those devices

#### Scenario: Duplicate role rejected
- **WHEN** the operator assigns `ledger` to a second disk
- **THEN** the wizard re-prompts for that disk, naming the disk that already carries `ledger`

#### Scenario: Unassigned role caught
- **WHEN** all detected disks are assigned or skipped but `snapshots` is still unassigned
- **THEN** the wizard reports the missing role and restarts the assignment loop rather than generating a broken playbook

### Requirement: Assignment-derived hybrid layouts
The disks block, mount dirs, and path variables SHALL be derived from the assignment map: each used disk gets one mount dir — `/mnt/solana` when it carries all three roles, `/mnt/solana_<role>` for a single role, `/mnt/solana_` + the roles joined with `_` (in ledger/accounts/snapshots order) for a shared disk — and the disks list contains one entry per role (with its `subdir`/`startup_arg`) pointing at its disk's mount dir, sharing entries idempotently exactly as the single-disk layout does. Path variables point at `<mount_dir>/<role>`. Generated playbooks SHALL satisfy the playbook variable contract and pass CI unchanged.

#### Scenario: Hybrid two-disk mapping
- **WHEN** disk A is assigned `ledger` and disk B is assigned `accounts,snapshots`
- **THEN** the playbook mounts A at `/mnt/solana_ledger` (one entry) and B at `/mnt/solana_accounts_snapshots` (two shared entries with distinct subdirs), with `ledger_path: /mnt/solana_ledger/ledger`, `accounts_path: /mnt/solana_accounts_snapshots/accounts`, `snapshots_path: /mnt/solana_accounts_snapshots/snapshots`

#### Scenario: Assignment equals a classic layout
- **WHEN** the assignment maps to exactly the `separate` or `single` shape
- **THEN** the generated disks block and paths are byte-identical to that classic layout's output
