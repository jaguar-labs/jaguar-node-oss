## MODIFIED Requirements

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