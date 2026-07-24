# Proposal: wizard-manual-disk

## Why

Some operators prepare NVMe storage themselves (the README has always said disk setup is "leased to the operators", and a real single-disk host was just provisioned this way by hand). Today they must know to flip `disk_management.mount`, run the right `mkfs`/`mount`/fstab commands with the right options, and keep paths consistent — knowledge that lives in chat logs and heads. A `manual` disk mode in the wizard generates the correct playbook *and* hands the operator the exact commands for their devices.

## What Changes

- The wizard's **disk layout** prompt gains a third option: `manual` (alongside `separate`/`single`).
  - Manual mode asks the same shape question (one disk or three) and the device name(s), exactly like the automated modes.
  - The generated playbook sets `disk_management.mount: False, config: True` — the role never formats or mounts (the operator did), but still creates the `ledger`/`accounts`/`snapshots` subdirs with `solana` ownership on the pre-mounted disk(s). Path variables are identical to the corresponding automated layout.
- The wizard **prints the manual setup commands** — `mkfs.xfs`, `mount` with the repo's tuned options, UUID-based fstab entry, `mount -a` verification — filled in with the operator's actual devices and mount dirs, and **saves them to `playbooks/disk-setup-<name>.sh`** next to the generated playbook.
  - The script refuses to run without an explicit `--yes` flag (it contains `mkfs`, which destroys data) and re-prints itself when invoked without it.
- Template impact: none — manual mode reuses the existing `@@DISK_MANAGEMENT_DISKS@@` block token (rendering `mount: False, config: True` requires tokenizing those two flags: `@@DISK_MOUNT@@`, `@@DISK_CONFIG@@`; automated modes render `True`/`True`, keeping output byte-identical).
- Round-trip guard: regenerating the sample (separate mode) must still produce an empty diff.

## Capabilities

### New Capabilities

<!-- none -->

### Modified Capabilities

- `playbook-generation`: the essential-prompts requirement gains the `manual` layout option, and a new requirement covers manual-mode semantics (mount/config flags, command script generation, destructive-command guard).

## Impact

- `bin/new-playbook.sh` — third layout branch, command renderer, setup-script writer.
- `playbooks/templates/profile.yaml.tmpl` — `mount`/`config` become tokens (output-neutral for existing modes).
- `.gitignore` — `playbooks/disk-setup-*.sh` excluded (host-specific operator artifacts, like generated playbooks they may or may not be committed; default to ignored).
- No role changes: `disks_mount.yaml` already supports `mount: False, config: True` (the skipped-item label bug it exposed was fixed separately).
