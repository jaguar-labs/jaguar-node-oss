# host-storage-preparation Specification

## Purpose
TBD - created by syncing change `storage-paths-only`. Defines the split between operator-run disk preparation (the wizard-generated disk-setup script) and Ansible's storage responsibilities, which are limited to guaranteeing directories on already-prepared mounts.

## Requirements

### Requirement: Ansible never touches block devices
No role SHALL format filesystems, mount or unmount block devices or tmpfs, or edit `/etc/fstab`. Block-device preparation (format, mount, fstab persistence) happens exclusively via the operator-run, wizard-generated `disk-setup-<name>.sh` executed on the target host before provisioning. The `disk_management` and `ramdisk_management` structures SHALL NOT exist in playbooks or roles.

#### Scenario: Playbook run cannot format anything
- **WHEN** any playbook in the repo runs against a host, with any variable values
- **THEN** no task invokes mkfs/filesystem/mount modules or commands — the class of incident where an unedited example file formats a disk is structurally impossible

#### Scenario: Ramdisk removed
- **WHEN** the playbook provisions a host
- **THEN** no tmpfs is mounted (the former 120 GB `accounts_index` ramdisk, whose startup arg nothing consumed, is gone); existing hosts keep any mounted tmpfs until they unmount or reboot

### Requirement: The validator role guarantees storage directories
The validator role SHALL create the three storage directories (`ledger_path`, `accounts_path`, `snapshots_path`) with `{{ solana_user }}` ownership and `0755` mode on every run — the role's only storage responsibility.

#### Scenario: Directories on prepared mounts
- **WHEN** the operator has run the disk-setup script and the playbook runs
- **THEN** all three directories exist on the mounted filesystems, owned by the solana user

#### Scenario: Ownership repair
- **WHEN** a mount was re-created (e.g. re-mounted disk with root-owned filesystem root) and the playbook re-runs
- **THEN** the directories are re-created/re-owned correctly — the permission-denied-at-validator-start class of failure is fixed by a playbook run

### Requirement: Unprepared storage is flagged, not hidden
Before creating the directories, the role SHALL check whether each path's mount directory (its first two path components, e.g. `/mnt/solana_ledger`) is an active mountpoint, and SHALL emit a clearly visible warning naming the disk-setup script when it is not. The play SHALL NOT fail on this check (deliberate on-root-filesystem layouts remain possible for test rigs).

#### Scenario: Forgot the setup script
- **WHEN** the playbook runs on a host where the assigned disks were never formatted/mounted
- **THEN** the run continues but prints a warning per unmounted path pointing at `disk-setup-<name>.sh`, and the directories are created on the root filesystem
