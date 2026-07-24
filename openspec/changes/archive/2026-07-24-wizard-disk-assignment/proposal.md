# Proposal: wizard-disk-assignment

## Why

The wizard already detects unused disks but only uses them as prompt defaults inside three fixed layouts (`separate`/`single`/`manual`). Real hosts have arbitrary disk counts — two large NVMes, four small ones — and the natural operator question is per-disk ("what should this disk do?"), not per-layout. An interactive assignment flow turns detection into configuration: the wizard shows what it found, asks how to use each disk, and generates the matching playbook — including hybrid mappings (e.g. ledger alone on one disk, accounts+snapshots sharing another) that no fixed layout can express today.

## What Changes

- **New disk-assignment flow in `bin/new-playbook.sh`**, offered automatically when unused disks are detected: for each detected disk (shown with size), the operator assigns one or more roles — `ledger`, `accounts`, `snapshots`, `all` (everything), or `skip`. The wizard validates the result (every role assigned exactly once across disks) and re-prompts on conflicts or gaps.
- **Hybrid layout generation**: the `disk_management.disks` block, mount dirs, and the three path variables are derived from the assignment — one mount per used disk (`/mnt/solana` when a disk carries all three roles, `/mnt/solana_<role>` for a single role, `/mnt/solana_<role1>_<role2>` for shared disks), with one disks-list entry per role pointing at its disk's mount dir. The existing role loop handles shared-disk entries idempotently (proven by the single-disk layout).
- **Existing flows remain**: the operator can decline assignment (or no disks are detected) and fall back to the current layout prompt (`separate`/`single`/`manual`); the assignment flow also asks whether the playbook should format/mount (automated) or the operator prepares disks themselves (manual semantics: `mount: False, config: True` + the generated `disk-setup-<name>.sh` covering exactly the assigned disks).
- Round-trip guard as always: regenerating the sample via the classic separate layout must produce an empty diff.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `playbook-generation`: the detection requirement upgrades from "propose defaults" to "offer interactive assignment"; a new requirement defines assignment semantics, validation, and hybrid-layout generation.

## Impact

- `bin/new-playbook.sh` — assignment prompt loop, role-to-disk validation, generalized disks-block/path/setup-script renderers keyed on the assignment map instead of the layout enum.
- No template changes expected (the block/path/flag tokens are already general).
- `README.md` — document the assignment flow.
- No role changes; generated output for the classic layouts is unchanged.
