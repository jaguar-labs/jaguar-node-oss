# Design: wizard-single-disk

## Context

The wizard generates a fixed three-disk `disk_management` block. Single-NVMe hosts need one device mounted once with three subdirs. The validator role's `disks_mount.yaml` iterates `disk_management.disks` per entry (create mount dir → detect fstype → conditional format → mount by UUID → create subdir), so the data structure is the design surface — the role need not change.

## Goals / Non-Goals

**Goals:**
- One new prompt; single-disk playbooks correct end-to-end, including utility scripts.
- Separate-disk output remains byte-identical (proven by regenerating the sample).

**Non-Goals:**
- Role changes, partition/LVM management, or per-subdir sizing.
- Custom mount points or arbitrary disk counts (two layouts only).
- Migrating existing deployed hosts between layouts.

## Decisions

1. **Single-disk = three `disks` entries sharing `dev` + `mount_dir: /mnt/solana`, distinct `subdir`/`startup_arg`.** The role's loop then: creates `/mnt/solana` (idempotent ×3), formats at most once (subsequent iterations see the target fstype and skip via the existing `item.stdout != item.item.fs_type` condition), mounts the same UUID at the same path (`state: mounted` is a no-op after the first), and creates each subdir. Alternative — teach the role a `subdirs:` list — rejected: touches host-facing task logic for zero functional gain; the shared-entry encoding is pure data.
2. **Template gains `@@DISK_MANAGEMENT_DISKS@@` (block token) and `@@LEDGER_PATH@@`/`@@ACCOUNTS_PATH@@`/`@@SNAPSHOTS_PATH@@` (scalar tokens).** The wizard renders the disk block from a layout-specific function, following the existing `@@ENTRYPOINTS_BLOCK@@` pattern. The three `*_DEV` scalar tokens are replaced by the block token (devices now live inside the rendered block).
3. **Mount point `/mnt/solana` for single mode.** Matches the repo's `/mnt/solana_*` naming family; `validator_log_path` default (`/mnt/solana/log`) already lives there on such hosts — acceptable co-location, and the log path remains independently promptable.
4. **Utility-script templating fixes ship in this change** (`dl-snapshots.sh.j2` DEFAULT_OUTPUT_DIR → `{{ snapshots_path }}`; `node-transition.sh.j2` tower check → `{{ ledger_path }}`). For existing separate-disk deployments the rendered values are identical, so this is behavior-preserving where it's already deployed and corrective where it was broken (any host with non-default paths).
5. **Ramdisk (accounts_index tmpfs) is unaffected** — it's RAM, not disk, and stays as-is in both layouts.

## Risks / Trade-offs

- [Same-device triple iteration confuses a future role refactor] → The generated block carries a YAML comment (`# single-disk layout: entries share one device; role loop is idempotent`) so the intent is visible in the playbook itself.
- [Single disk means ledger/accounts/snapshots I/O contention] → Inherent to the hardware choice, not the tooling; the wizard prints a one-line note that separate NVMes are recommended for mainnet.
- [`force: true` on a shared device is scarier than on dedicated devices] → Unchanged semantics from the existing template (format only fires when fstype differs), but the single-disk block keeps `force: true` consistent with current behavior; the wizard's "review the generated playbook" next-step note already covers it.
- [Round-trip regression in separate mode] → Explicit task regenerates the sample and requires an empty diff (the template refactor must be exactly output-neutral).

## Migration Plan

1. Template refactor + wizard changes + utility-script fixes in one commit; regenerate sample (diff must be empty).
2. CI validates as before (yamllint/ansible-lint/syntax-check on the sample; shellcheck on the wizard).
3. Rollback: revert the commit; previously generated playbooks are unaffected either way.

## Open Questions

- None.
