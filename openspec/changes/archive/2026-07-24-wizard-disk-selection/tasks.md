# Tasks: wizard-disk-selection

## 1. Selection-first flow

- [x] 1.1 Replace the y/n offer + per-disk skip loop in `bin/new-playbook.sh`: numbered disk listing, selection prompt (indices/paths comma-separated, `all` default, `none` → classic flow), validated (known, deduped, 1–3)
- [x] 1.2 Role prompts over selected disks only (no `skip`), defaults by selection count (1→all; 2→ledger / accounts,snapshots; 3→one each); duplicate/unknown re-prompt naming the conflicting disk; missing roles restart role prompts keeping the selection

## 2. Docs

- [x] 2.1 README: selection-first wording (`none` escape, numbered selection)

## 3. Verification

- [x] 3.1 e2e matrix updated to the new sequence: select-all + one-role-each ≡ separate; single-disk `all`; hybrid `1,2` → ledger / accounts,snapshots; `none` → classic; invalid selection (unknown index, >3) re-prompts; duplicate-role and missing-role paths; one-disk `skip`-equivalent (select `none`) proves the old trap is gone
- [x] 3.2 Round-trip: sample regeneration empty diff; manual-mode assignment still generates the setup script
- [x] 3.3 shellcheck + yamllint clean; commit, push, CI green

## 4. Last-disk coverage (field follow-up)

- [x] 4.1 Last selected disk's prompt defaults to the still-unassigned roles and rejects answers that don't cover them (naming the missing roles) — under-assignment corrected in place, no restart loop
- [x] 4.2 e2e: one-disk `ledger` answer rejected then Enter completes; two-disk under-assign rejected naming the missing role; matrix cases and sample round-trip unchanged; lint + CI green