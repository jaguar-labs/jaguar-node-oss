# Proposal: wizard-role-placement

## Why

Field verdict on the disk flow: it doesn't work well enough. The disk-first framing (select disks, then assign roles) inverts how operators think, plain-text prompts make choices easy to mistype, and there is no way to place a role on an *existing* filesystem. The flow should ask the operator's actual questions, role by role, with arrow-key selectable choices.

## What Changes

- **Role-first placement flow** replacing the selection-first assignment *and* the classic `separate`/`single` layout prompts:
  1. **Ledger** — "Where do you want to put ledger?" → menu: `unused disk` / `existing location`. Unused disk → arrow-pick from the detected disks (device + size) → location prompt defaulting to `/mnt/solana_ledger/ledger` (the disk is formatted/mounted at the location's parent dir by the setup script). Existing location → path prompt with the same default, no disk preparation.
  2. **Snapshots** — menu: `with ledger` (default) / `unused disk` / `existing location`. **`with ledger` omits the `--snapshots` argument from the start script** — agave's default snapshot location is the ledger dir, and per the minimal-flags convention a flag equal to the default must not appear; `snapshots_path` follows `ledger_path` so utilities and directory creation stay correct. Otherwise: same ceremony as ledger, default `/mnt/solana_snapshots/snapshots`.
  3. **Accounts** — same ceremony as ledger, default `/mnt/solana_accounts/accounts`. **Accounts are never co-located with ledger**: a location resolving under the ledger mount is rejected with a message (accounts always live on their own disk/mount).
- **Arrow-key menus** (`↑`/`↓` + Enter) for **all fixed-choice prompts** — cluster selection, every yes/no toggle (Jito, XDP, vault creation), the Jito region, the placement menus and disk pickers — via a reusable `menu_select` helper reading tty escape sequences, with a **non-tty fallback** to numbered plain-text input that also accepts the legacy labels (`y`/`n`, cluster names, region names) so existing scripted sequences keep working.
- A disk already placed is removed from later pickers (one disk = one mount); sharing a disk between roles is expressed via `existing location` under the first role's mount.
- The disk-setup script is generated only when at least one role landed on an unused disk, covering exactly those disks at the chosen mount dirs.
- All three start-script templates make `--snapshots` conditional on `snapshots_path != ledger_path`.

## Capabilities

### Modified Capabilities

- `playbook-generation`: the detection requirement feeds the unused-disk picker; the selection-first assignment, hybrid-layout, and single-disk requirements are superseded by role-first placement requirements (placement flow, menu interaction contract, snapshots-with-ledger semantics, setup-script scope).

## Impact

- `bin/new-playbook.sh`: `menu_select` helper, role-placement flow replacing the assignment + classic layout blocks, per-role location state replacing the role→disk map's derived mount dirs.
- `roles/validator/templates/start-node*.sh.j2` (all three): conditional `--snapshots`.
- e2e matrix rewritten for the new prompt sequence (non-tty fallback path); the sample playbook is **regenerated with the new defaults** — snapshots ride with ledger (`snapshots_path == ledger_path`, no `--snapshots` in its rendered start script), an intentional showcase diff.
- README wizard section updated.
