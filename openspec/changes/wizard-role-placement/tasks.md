# Tasks: wizard-role-placement

## 1. Menu helper

- [ ] 1.1 Add `menu_select` to `bin/new-playbook.sh`: arrow-key navigation (↑/↓ + Enter, default pre-highlighted, in-place redraw, cursor restored on abort) when fd 3 is a tty; numbered plain-text listing accepting number-or-label otherwise

## 2. Role-first placement flow

- [ ] 2.1 Replace the selection-first assignment and classic layout blocks with the role-first flow: ledger (`unused disk`/`existing location`), snapshots (`with ledger` default /`unused disk`/`existing location`), accounts (as ledger) — location prompts with the per-role defaults (`/mnt/solana_ledger/ledger`, `/mnt/solana_snapshots/snapshots`, `/mnt/solana_accounts/accounts`), absolute-path validation
- [ ] 2.2 Unused-disk pickers fed by detection, placed disks removed from later pickers (with a hint to use `existing location` for sharing); `unused disk` option absent when nothing is detected
- [ ] 2.3 Placement state `(source, device, path)` per role; `snapshots_path = ledger_path` for `with ledger`; setup script generated only for unused-disk placements, mounting each device at `dirname(location)`; next-steps disk-prep step only when a script was produced

## 3. Start templates

- [ ] 3.1 All three start templates (`start-node.sh.j2`, `start-node-jito.sh.j2`, `start-node-alpenglow.sh.j2`): wrap `--snapshots` in `{% if snapshots_path != ledger_path %}`

## 4. Docs

- [ ] 4.1 README wizard section: role-first placement, arrow-key menus (and the numbered fallback), snapshots-with-ledger default and its minimal-flags rationale

## 5. Verification

- [ ] 5.1 e2e (numbered fallback): mixed placement (disk + with-ledger + existing) asserting paths, setup-script scope, and `--snapshots` omission via template render; defaults-on-three-disks case; no-unused-disks case (locations only, no script); picker-dedupe case
- [ ] 5.2 Round-trip: sample regenerated with explicit answers reproducing current paths — byte-identical; template render check for both `--snapshots` branches on all three templates
- [ ] 5.3 shellcheck + yamllint clean; commit, push, CI green