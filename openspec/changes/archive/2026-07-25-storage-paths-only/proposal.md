# Proposal: storage-paths-only

## Why

A near-miss in the field: running the sample playbook unedited attempted `mkfs.xfs` on the sample's static example devices — the OS disk survived only because it was busy, a nonexistent device errored the play, and one bare disk *was* formatted. A config file should never be one command away from formatting block devices. Separately, `ramdisk_management` mounts a 120 GB tmpfs whose `accounts-index-path` startup arg is consumed by nothing — pure dead weight that reserves RAM.

## What Changes

- **Ansible stops touching block devices entirely.** `disk_management` (enable/mount/config flags, per-disk dev/fstype/options entries) is removed from the template, sample, and role. The validator role keeps exactly one storage responsibility: create the three path directories (`ledger_path`, `accounts_path`, `snapshots_path`) with `solana` ownership — locations only, as configuration should be.
- **Formatting and mounting always happen pre-playbook via the wizard-generated `disk-setup-<name>.sh`.** The wizard's disk flow (detection, selection-first assignment, hybrid mount-dir derivation) is unchanged, but its output changes meaning: it *always* generates the setup script for the assigned disks (the automated-vs-manual question disappears — there is no automated mode anymore), and the playbook it generates contains only the three paths.
- **Safety net in the role**: before creating the path directories, warn (not fail) when a path's mount directory is not an active mountpoint — catching "forgot to run the disk-setup script" with a pointer to it, while still allowing deliberate on-root-fs layouts (dev/test boxes).
- **`ramdisk_management` is removed**: the role task, the template/sample block, and the tmpfs mount. (Existing hosts keep their mounted tmpfs until reboot/manual unmount; nothing referenced it.)
- **BREAKING** for anyone relying on the playbook to format/mount disks: the README and wizard next-steps make the new order explicit — run `disk-setup-<name>.sh` on the host (as root, `--yes`) *before* the playbook.

## Capabilities

### New Capabilities

- `host-storage-preparation`: the contract that block-device work (format, mount, fstab) happens only via the operator-run generated script; the playbook consumes paths and guarantees directories/ownership; the mountpoint warning.

### Modified Capabilities

- `playbook-generation`: manual/automated distinction removed from prompts and generation (the disk flow always emits paths + setup script); `disk_management`/`ramdisk_management` no longer appear in generated playbooks; single-disk/manual/hybrid requirements rewritten in path terms.

## Impact

- `playbooks/templates/profile.yaml.tmpl` + sample: `disk_management` and `ramdisk_management` blocks removed (template loses the disks/mount/config tokens); three path vars remain.
- `bin/new-playbook.sh`: automated/manual question removed; setup script always generated for assigned/entered disks; `DISK_MOUNT`/`DISK_CONFIG` tokens dropped.
- `roles/validator`: `disks_mount.yaml` and `ramdisk.yaml` replaced by a small `storage_dirs.yaml` (create three dirs + ownership + mountpoint warning); `main.yaml` imports updated.
- Specs: `playbook-generation` heavily revised; new `host-storage-preparation`.
- Existing provisioned hosts: no change (their disks are already formatted/mounted; the role now just re-asserts directories). The formatting near-miss class of incident becomes structurally impossible.
