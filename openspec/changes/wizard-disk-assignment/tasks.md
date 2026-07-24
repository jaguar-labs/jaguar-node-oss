# Tasks: wizard-disk-assignment

## 1. Map-driven renderer refactor (output-neutral)

- [ ] 1.1 In `bin/new-playbook.sh`, introduce the role→disk map (`ROLE_DISK_ledger/accounts/snapshots`) and a mount-dir derivation function (all roles → `/mnt/solana`; one role → `/mnt/solana_<role>`; two → `/mnt/solana_<r1>_<r2>` in canonical order)
- [ ] 1.2 Rewrite the disks-block, path-derivation, and disk-setup-script renderers to iterate the map (one entry per role, shared mount dirs deduped); classic `separate`/`single`/`manual` flows populate the map instead of branching
- [ ] 1.3 Prove neutrality: regenerate the sample (empty diff) and compare `single` + `manual single` specimens byte-for-byte against pre-refactor generations

## 2. Assignment flow

- [ ] 2.1 After detection, when unused disks exist, offer "Configure detected disks interactively? (y/n)"; decline → existing layout prompt with detected defaults
- [ ] 2.2 Per-disk prompt loop: accept `all`, `skip`, or comma-separated role subset; strict token validation with per-token errors; duplicate-role rejection naming the conflicting disk
- [ ] 2.3 Post-loop completeness check: report any unassigned role and restart the loop; then the automated/manual question (manual → `mount: False, config: True` + setup script over the assigned disks)
- [ ] 2.4 Feed the resulting map into the shared renderers; confirm the generated playbook parses and self-checks pass

## 3. Docs

- [ ] 3.1 README: document the assignment flow (when it appears, role tokens, hybrid mount-dir naming, automated vs manual outcome)

## 4. Verification

- [ ] 4.1 Scripted e2e matrix: (a) 3 disks × one role each ≡ separate output; (b) 1 disk × `all` ≡ single output; (c) 2-disk hybrid (`ledger` / `accounts,snapshots`) — assert entries, mount dirs, and paths per spec; (d) duplicate-role retry; (e) missing-role restart; (f) decline → classic flow
- [ ] 4.2 Manual-mode assignment e2e: hybrid map generates `disk-setup-<name>.sh` covering exactly the two assigned disks with correct mount dirs; `--yes` guard intact
- [ ] 4.3 shellcheck + yamllint + pinned ansible-lint clean; commit, push, CI green

Note: e2e runs need a way to simulate detected disks (the dev box has none) — inject via a test hook (e.g. `NEW_PLAYBOOK_FAKE_UNUSED_DISKS` env var consumed only when set) so the assignment path is testable; document the hook as test-only.
