# Design: storage-paths-only

## Context

Field near-miss: the sample playbook's static example devices met a real server — `mkfs` on the OS disk was stopped only by "device busy", a nonexistent device failed the play, one bare disk was formatted. Separately, the `ramdisk_management` tmpfs (120 GB) is consumed by nothing (its `accounts-index-path` startup arg appears in no start script). The wizard already generates a guarded disk-setup script for manual mode; this change makes that the only path and strips Ansible of block-device powers.

## Goals / Non-Goals

**Goals:**
- Generated playbooks contain storage *locations* only; formatting/mounting is always operator-run script, pre-playbook.
- Remove `disk_management` and `ramdisk_management` everywhere; role keeps directory creation + ownership + a not-mounted warning.
- The formatting-by-config-file incident class becomes structurally impossible.

**Non-Goals:**
- Changing the wizard's disk selection/assignment UX or hybrid mount-dir naming (only its output changes).
- Ramdisk/accounts-index tuning as a future feature (if ever wanted, it returns as a deliberate change with a consumer).
- Unmounting existing tmpfs on provisioned hosts (left to reboot/operator).

## Decisions

1. **Delete, don't gate.** Rather than defaulting `disk_management.mount` to False, the structures are removed entirely — a safety property enforced by absence is stronger than one enforced by a flag someone can flip back. The role's `disks_mount.yaml` and `ramdisk.yaml` are replaced by one small `storage_dirs.yaml`.
2. **The role keeps directory creation** (the old `config: True` behavior, now unconditional): it runs after the `solana` user exists, fixing the mkdir/chown timing problem, and repairs ownership after re-mounts — the permission-denied failure seen in the field.
3. **Mountpoint check warns, never fails** (`findmnt`-based, `changed_when: false`): failing would break deliberate root-fs test layouts; warning with the script name catches the real mistake (forgot to prepare disks) at the earliest visible moment.
4. **Wizard: the automated/manual question disappears.** Selection/assignment (or classic layout prompts) now feed only path derivation + script generation. `DISK_MOUNT`/`DISK_CONFIG` and `@@DISK_MANAGEMENT_DISKS@@` tokens leave the template; `MANUAL_SETUP` branching collapses to "always".
5. **Sample playbook regenerates without any device references** — an unedited sample run can no longer touch block devices, which is the entire point.
6. **rpc role note**: it shares `disk_management` via defaults? (Verified: rpc role has no disk tasks — no impact.) The `community.general.filesystem` dependency may become unused; `requirements.yml` keeps `community.general` (cargo still uses it).

## Risks / Trade-offs

- [Operators accustomed to playbook-managed disks are surprised] → BREAKING note in README + wizard next-steps ordering ("run disk-setup first"); the role's warning names the script when disks aren't prepared.
- [Existing playbooks in the wild still carry disk_management] → The role simply ignores unknown vars; their disks are already prepared, so behavior converges.
- [Removing the ramdisk changes host memory profile] → It frees 120 GB of potential tmpfs usage; nothing referenced the mount, so no validator behavior changes.
- [Sample diff is large] → Intentional and reviewed via the round-trip regeneration.

## Migration Plan

1. Template/sample/wizard/role changes + spec sync in one change; e2e regenerates all layouts and asserts no `disk_management`/`ramdisk_management` anywhere; CI as usual.
2. Existing hosts: next playbook run skips nothing dangerous (there is nothing dangerous left); directories re-asserted; tmpfs unaffected until reboot.
3. Rollback: revert the commit.

## Open Questions

- None.
