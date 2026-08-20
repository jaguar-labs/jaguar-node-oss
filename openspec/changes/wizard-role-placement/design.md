# Design: wizard-role-placement

## Context

Field verdict: the disk-first flow (select disks → assign roles) doesn't match how operators think and its plain-text prompts are error-prone. The user specified the target UX: per-role questions (ledger → snapshots → accounts), arrow-key menus, an `existing location` option, and snapshots defaulting to co-location with ledger — in which case the `--snapshots` flag must disappear from start scripts (it would restate agave's default, violating the repo's minimal-flags convention).

## Goals / Non-Goals

**Goals:**
- Role-first placement exactly as specified; arrow-key menus with the default pre-highlighted.
- Scripted/e2e use keeps working via a non-tty numbered fallback.
- Storage contract unchanged downstream: three path vars, script-first disk prep, Ansible never touches block devices.

**Non-Goals:**
- Arrow-key treatment for free-text prompts (paths, pubkeys) — only fixed-choice menus.
- Formatting/mounting for `existing location` placements (existing means mounted and ready).
- Changing the disk-setup script's content per disk (same mkfs/mount/fstab commands, now scoped to placed disks).

## Decisions

1. **`menu_select` helper**: renders options with the default highlighted, reads from fd 3; on `[ -t 3 ]` it processes `ESC [ A/B` sequences and Enter with a redraw-in-place loop (`read -rsn1`), restoring the cursor with a trap; otherwise it prints a numbered list and reads one line (number or exact label). All existing scripted e2e sequences therefore keep the one-line-per-prompt shape.
2. **Placement state is three `(source, device, path)` records** — replacing the role→disk map and derived mount-dir naming. The mount dir for an unused-disk placement is `dirname(location)`; the setup script iterates placed devices (deduplication is structural: placed disks leave the picker).
3. **Snapshots co-location is expressed as `snapshots_path == ledger_path`** — no new playbook variable. Start templates gain `{% if snapshots_path != ledger_path %}` around `--snapshots`; utilities (`dl-snapshots.sh` default dir) and `storage_dirs.yaml` need no change (creating the ledger dir twice is idempotent). The variable contract (all three paths defined and asserted) is untouched.
4. **One disk, one mount**: a device placed for one role is removed from later pickers. Mounting one device at two dirs is impossible; sharing is `existing location` under the earlier role's mount (message printed when the picker empties).
5. **Accounts are never co-located with ledger** (user decision): the accounts ceremony matches ledger's, but a location resolving under the ledger mount is rejected with a message — accounts always get their own disk/mount. Validation: the accounts location's mount dir (path prefix) must differ from ledger's.
6. **Old flows are deleted, not kept as fallbacks** — the classic `separate`/`single` prompt and the selection-first assignment both go; keeping three disk flows would triple the e2e surface for no operator value. The no-unused-disk case degenerates naturally to three location prompts.
7. **All fixed-choice prompts become menus** (user decision): cluster, Jito/XDP/vault yes-no toggles, Jito region, placement menus, disk pickers. The non-tty fallback accepts option numbers *and* labels including the legacy tokens (`y`/`n`, cluster names, region names), so most existing scripted sequences survive unchanged; `prompt_yn` becomes a two-option menu wrapper.
8. **The sample showcases the new defaults** (user decision): it is regenerated with snapshots `with ledger` — `snapshots_path` equals `ledger_path` and its rendered start script has no `--snapshots`. The round-trip guard pins the *new* committed sample (regeneration with default answers must reproduce it exactly); the old byte-identical-to-previous guard is intentionally retired for this change.

## Risks / Trade-offs

- [Terminal escape handling is finicky (terminals, ssh, tmux)] → Only `↑`/`↓`/Enter are interpreted; anything else falls through to the numbered fallback path; non-tty detection is per-fd and conservative (fallback is always correct, arrows are the enhancement).
- [e2e sequences change again] → Rewritten in the same commit; the numbered fallback keeps them plain-text.
- [Sample diff is sizeable (new defaults)] → Intentional showcase (user decision); the diff is reviewed against the mixed-placement spec scenario, and the new sample becomes the round-trip baseline.
- [`--snapshots` omission changes deployed behavior for co-located playbooks] → That is the point (minimal flags); existing playbooks are untouched until regenerated.

## Migration Plan

1. Helper + flow + template conditionals + e2e rewrite in one commit; sample round-trip with explicit answers stays byte-identical; CI as usual.
2. Existing playbooks unaffected; new/regenerated ones use the new flow.
3. Rollback: revert the commit.

## Open Questions

- None.
