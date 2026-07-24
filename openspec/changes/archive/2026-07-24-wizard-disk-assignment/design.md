# Design: wizard-disk-assignment

## Context

The wizard has three fixed layouts, unused-disk detection feeding prompt defaults, manual-mode semantics (`mount: False, config: True` + generated setup script), and fully tokenized disk/path template slots. This change reorganizes the *prompt flow* around detected disks; the generation machinery is already general enough.

## Goals / Non-Goals

**Goals:**
- Per-disk role assignment with strict validation; hybrid mappings (any role→disk partition of the three roles).
- Assignment composes with the automated/manual choice and the setup-script generation.
- Classic flows byte-identical when unchosen; sample round-trip stays empty-diff.

**Non-Goals:**
- Assigning roles to *used* disks (detection scope unchanged — bare disks only).
- Splitting a single role across disks, RAID/LVM, custom mount points, per-role fs options.
- Changing the ramdisk (accounts_index) handling.

## Decisions

1. **Assignment is an offer, not a replacement.** Detected disks → "Configure these disks interactively? (y/n)"; decline falls back to the existing layout prompt (which keeps detected-disk defaults). Zero-disk machines see no change. This keeps scripted/CI runs and muscle memory intact.
2. **Roles are the unit, disks are the container.** Internally the flow builds `ROLE_DISK[ledger|accounts|snapshots] = /dev/...`; validation is "each role exactly once" — simpler and stricter than validating per-disk strings, and duplicate/missing detection falls out naturally.
3. **Mount-dir naming is derived, deterministic, and collision-free**: all three roles → `/mnt/solana`; one role → `/mnt/solana_<role>` (matches the classic separate layout exactly); two roles → `/mnt/solana_<r1>_<r2>` in canonical ledger/accounts/snapshots order. Because names derive from role sets and each role appears once, no two disks can produce the same mount dir.
4. **Renderers key on the role→disk map, not the layout enum.** `disk_entry`/`disk_setup_cmds`/path derivation already take (mount_dir, dev, subdir) arguments; the classic layouts become two fixed maps feeding the same generalized renderer — one code path, and the "assignment equals classic layout" spec scenario is enforced by construction.
5. **Automated-vs-manual is asked once, after assignment** — reusing the exact manual-mode semantics (flags + setup script). The setup script generator iterates the same map, so hybrid manual layouts get correct per-disk commands for free.
6. **No template changes.** `@@DISK_MANAGEMENT_DISKS@@`, `@@DISK_MOUNT@@`/`@@DISK_CONFIG@@`, and the three path tokens already carry everything; this is wizard-side only.

## Risks / Trade-offs

- [Prompt-flow complexity creeps into a 400-line bash script] → The map-driven refactor (decision 4) *removes* the layout branching from the renderers; net structural complexity is roughly flat. Shellcheck + the scripted e2e matrix guard regressions.
- [Comma-separated role input invites typos] → Strict parse against the known role names with per-token error messages; `all` and `skip` as unambiguous shortcuts.
- [Scripted e2e now needs assignment-path coverage] → Assignment prompts are plain reads on fd 3, so the existing printf-pipe testing pattern works; add matrix cases (3×1-role, 1×all, 2-disk hybrid, duplicate-role retry, decline-fallback).
- [Hybrid mount dirs are new on-host paths] → Derived names are stable and documented; utility scripts already consume `snapshots_path`/`ledger_path` variables, not hardcoded mounts (fixed in wizard-single-disk).

## Migration Plan

1. Refactor renderers to the role→disk map; verify classic layouts byte-identical (regenerate sample, compare a `single` specimen against pre-change output).
2. Add the assignment flow; e2e matrix; README.
3. CI as usual; rollback = revert (classic flows unaffected by construction).

## Open Questions

- None.
