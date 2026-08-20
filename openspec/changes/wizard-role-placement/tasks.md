# Tasks: wizard-role-placement

## 1. Menu helper

- [x] 1.1 Add `menu_select` to `bin/new-playbook.sh`: arrow-key navigation (↑/↓ + Enter, default pre-highlighted, in-place redraw, cursor restored on abort) when fd 3 is a tty; numbered plain-text listing accepting number-or-label (incl. legacy tokens `y`/`n`, cluster/region names) otherwise
- [x] 1.2 Convert all fixed-choice prompts to `menu_select`: cluster, Jito enable + region, XDP enable, vault-creation toggle (`prompt_yn` becomes a two-option menu wrapper)

## 2. Role-first placement flow

- [x] 2.1 Replace the selection-first assignment and classic layout blocks with the role-first flow: ledger (`unused disk`/`existing location`), snapshots (`with ledger` default /`unused disk`/`existing location`), accounts (as ledger) — location prompts with the per-role defaults (`/mnt/solana_ledger/ledger`, `/mnt/solana_snapshots/snapshots`, `/mnt/solana_accounts/accounts`), absolute-path validation
- [x] 2.2 Unused-disk pickers fed by detection, placed disks removed from later pickers (with a hint to use `existing location` for sharing); `unused disk` option absent when nothing is detected
- [x] 2.3 Placement state `(source, device, path)` per role; `snapshots_path = ledger_path` for `with ledger`; setup script generated only for unused-disk placements, mounting each device at `dirname(location)`; next-steps disk-prep step only when a script was produced
- [x] 2.4 Accounts co-location guard: reject an accounts location under the ledger mount with a message (accounts always on their own disk/mount) and re-prompt

## 3. Start templates

- [x] 3.1 All three start templates (`start-node.sh.j2`, `start-node-jito.sh.j2`, `start-node-alpenglow.sh.j2`): wrap `--snapshots` in `{% if snapshots_path != ledger_path %}`

## 4. Docs

- [x] 4.1 README wizard section: role-first placement, arrow-key menus (and the numbered fallback), snapshots-with-ledger default and its minimal-flags rationale

## 5. Verification

- [x] 5.1 e2e (numbered fallback): mixed placement (disk + with-ledger + existing) asserting paths, setup-script scope, and `--snapshots` omission via template render; defaults-on-three-disks case; no-unused-disks case (locations only, no script); picker-dedupe case; accounts-under-ledger rejection; legacy-label answers (`y`/`n`, cluster names) still selecting correctly
- [x] 5.2 Regenerate the sample with default answers (snapshots with ledger — intentional showcase diff, review against the mixed-placement scenario, commit as the new round-trip baseline); template render check for both `--snapshots` branches on all three templates
- [x] 5.3 shellcheck + yamllint clean; commit, push, CI green