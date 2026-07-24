# Design: wizard-disk-selection

## Context

Field-found trap: with one detected disk, `skip` at the per-disk prompt left every role unassigned, and the completeness check restarted the loop with no exit. The per-disk `skip` token conflated two questions (which disks? what roles?) into one prompt.

## Goals / Non-Goals

**Goals:** selection-first prompts; `none` escape; unchanged downstream machinery; updated e2e matrix.
**Non-Goals:** changing detection, renderers, hybrid naming, or the automated/manual step.

## Decisions

1. **Selection replaces the y/n offer.** The old "Configure interactively? (y/n)" folds into the selection prompt itself: `none` is the decline. One less prompt; scripted inputs stay simple.
2. **Selection tokens: indices or device paths, `all`, `none`.** Indices match the numbered listing (what an operator reads); paths allow scripting without knowing order. Empty input = the shown default (`all`).
3. **Cap selection at 3, dedupe, reject unknowns** — three roles cannot occupy more than three disks; a 4th selected disk would be guaranteed dead weight and its role prompt unanswerable.
4. **Role prompts lose `skip`** — selecting a disk *is* the commitment to use it. Missing-role restarts re-run only the role prompts, keeping the selection (re-selecting would punish a role typo with full re-entry).
5. **Defaults by selection count** (1→`all`; 2→`ledger` / `accounts,snapshots`; 3→one each) make Enter-through produce a sensible layout at every count.

## Risks / Trade-offs

- [Scripted e2e sequences change] → All matrix cases updated in the same commit; the fake-disk hook is unchanged.
- [Numbered selection vs. path-based muscle memory] → Both accepted.

## Migration Plan

Single commit (wizard + e2e + README); round-trip sample guard as always (no detected disks on dev/CI → classic path untouched); rollback = revert.

## Open Questions

- None.
