# Design: wizard-manual-disk

## Context

The wizard supports `separate` and `single` automated disk layouts. Operators who pre-provision storage (a supported, README-documented workflow) currently hand-edit `disk_management.mount` and reconstruct mkfs/mount/fstab commands from memory or chat logs. A recent real provisioning surfaced both the need and a role bug (`loop_control.label` on skipped items — already fixed) in this path.

## Goals / Non-Goals

**Goals:**
- `manual` layout: correct playbook (`mount: False, config: True`) plus the exact, device-filled setup commands, printed and saved.
- Zero output change for the two automated layouts (empty-diff round-trip guard).

**Non-Goals:**
- Executing the disk commands from the wizard (they run on the target host as root; the wizard runs on the controller).
- Supporting exotic layouts (RAID, LVM, custom mount points, non-xfs) — the script is a starting point the operator can edit.
- Detecting the host's current disk state.

## Decisions

1. **Manual mode reuses the two existing shapes** (single/separate) via a follow-up prompt rather than free-form path entry. Keeps path derivation, disks-block rendering, and utility-script consistency identical to the automated modes; the only delta is two flags. Alternative — arbitrary user-supplied paths — rejected: multiplies untested combinations and breaks the "switch between manual and automated by flipping two flags" property.
2. **`mount: False, config: True`** (user decision): the role still creates subdirs and ownership *after* the `common` role has created the `solana` user, which removes the most error-prone manual steps (`mkdir`/`chown` timing).
3. **Template tokenizes the two flags** (`@@DISK_MOUNT@@`/`@@DISK_CONFIG@@`) instead of a second disks-block variant. Smallest possible template delta; automated modes substitute `True`/`True` so their output is byte-identical (guarded by the sample round-trip task).
4. **Setup script is generated data, not a repo template.** The wizard writes `playbooks/disk-setup-<name>.sh` from a heredoc with the answers substituted. It is gitignored: it is host-specific operator material, and committing files containing `mkfs` invocations invites copy-paste accidents. Printed to the terminal as well (user decision).
5. **`--yes` guard on the script**: without it, the script cats its own command section and exits 1. With it, commands run with `set -euo pipefail` and an `lsblk` echo of the target devices first. `mkfs.xfs` is invoked *without* `-f` — a disk that already has a filesystem fails loudly rather than being silently reformatted (the operator can add `-f` deliberately).
6. **fstab handling appends idempotently**: the script greps for the mount dir before appending, so re-runs don't duplicate entries.

## Risks / Trade-offs

- [Operator runs the script on the wrong host or device] → `--yes` guard, `lsblk` echo before formatting, no `-f` on mkfs, and the script names its target playbook in a header comment.
- [Script drifts from what the role would have done] → Both render from the same wizard variables in one run; the mount options string is a single shell constant (`DISK_FS_OPTIONS`) shared by the disks-block renderer and the script renderer.
- [Gitignored script gets lost] → It's regenerable: re-running the wizard with the same answers (`--force` for the playbook) reproduces it; the README says so.
- [Two flags tokenized → template token count grows] → Covered by the existing unfilled-token self-check; round-trip task proves neutrality.

## Migration Plan

1. Template tokenization + wizard branch + script renderer in one commit; regenerate sample (empty diff required); e2e scripted runs for manual single/separate.
2. CI validates lint + syntax as usual; shellcheck covers `bin/*.sh` (the generated script is checked by shellcheck-ing a generated specimen in the e2e task, not in CI).
3. Rollback: revert the commit; previously generated playbooks and scripts remain valid.

## Open Questions

- None.
