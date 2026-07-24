# Proposal: wizard-disk-selection

## Why

Field use exposed a trap in the assignment flow: with one detected disk, answering `skip` leaves all roles unassigned and the loop restarts forever — there is no path out to the classic prompts once assignment starts. The per-disk skip token also inverts the natural question order: operators think "which disks do I want to use?" first, then "what goes on each?".

## What Changes

- The assignment flow becomes **selection-first** (replacing the offer + per-disk-skip loop):
  1. Detected disks are listed numbered; one prompt asks **which to select** — numbers or device paths comma-separated, `all` (default), or `none` to fall back to the classic layout prompts. Selection is validated (1–3 disks; three roles can't spread further) and deduplicated.
  2. Each **selected** disk then gets a role prompt (`ledger`/`accounts`/`snapshots` comma-separated, or `all`) — no `skip` token: selecting a disk means using it. Sensible defaults by selection count (1 → `all`; 2 → `ledger` and `accounts,snapshots`; 3 → one role each).
  3. Duplicate/missing-role validation as before; missing roles restart the role prompts (selection is kept).
- `none` (or an empty selection) exits cleanly to the classic `separate`/`single`/`manual` flow — the infinite loop becomes impossible.
- Everything downstream (role→disk map, hybrid mount dirs, automated/manual question, setup script) is unchanged.

## Capabilities

### Modified Capabilities

- `playbook-generation`: the "Interactive disk assignment" requirement is restructured around selection-first; the detection requirement's offer wording updates accordingly.

## Impact

- `bin/new-playbook.sh` assignment block only; e2e matrix inputs updated to the new prompt sequence; README wording updated. No template, role, or renderer changes.
