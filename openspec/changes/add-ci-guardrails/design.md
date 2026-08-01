# Design: add-ci-guardrails

## Context

No automated checks exist. The controller must never run `ansible-playbook` (project rule), so CI is the only execution surface for verification. The codebase currently violates many ansible-lint production-profile rules (missing FQCN, `with_items`, k=v args, `ignore_errors`, `state: latest`), which are scheduled for a later idiom-sweep track — CI must be green now without hiding *new* regressions.

## Goals / Non-Goals

**Goals:**
- Green, meaningful CI on day one: yamllint + ansible-lint + syntax-check per playbook.
- Pinned, declared collection dependencies installable in one command.
- A lint debt ledger (`skip_list` with track annotations) that shrinks as modernization tracks land.

**Non-Goals:**
- Fixing existing lint violations (idiom-sweep track).
- Molecule/container converge testing — rejected per user decision (kernel/tuned/iptables/disk tasks can't run in containers; mocking cost too high).
- Publishing to Galaxy (`galaxy.yml`, role `meta/`) — later if ever.

## Decisions

1. **ansible-lint `production` profile + documented skip_list**, not a lax profile. The target bar is visible in config; debt is enumerated per-rule with a comment naming the track that removes it. Alternative — start at `basic` profile — rejected: it hides the real bar and gives no ratchet.
2. **Syntax-check with a dummy vault.** CI writes a throwaway vault password and a minimal encrypted (or `--vault-password-file /dev/null`-compatible dummy) `vault/secrets.yaml` so `vars_files` resolves during `--syntax-check`. Written defensively: if `vault/secrets.yaml` is absent (this change lands before `modernize-safety`), the step generates a plaintext dummy at that path. This makes the two changes order-independent.
3. **Matrix over playbooks via glob**, not a hardcoded list — the syntax-check step iterates `playbooks/*.yaml` so future profiles (e.g. an rpc playbook) are covered automatically.
4. **Version pins as ranges** (`community.general: ">=8.0.0,<11.0.0"`-style, exact ranges chosen at implementation time against the CI ansible-core version) rather than exact pins — collections are consumed, not vendored; ranges avoid weekly bump churn while excluding breaking majors.
5. **Single workflow file, three jobs** (yamllint, ansible-lint, syntax-check) rather than one mega-job — independent failure signals, parallel runtime, trivial to extend.
6. **README fix rides along.** The quick-start references a nonexistent playbook (`full-validator-mainnet-profile.yaml`) and a different repo URL; corrected here because CI badges and `requirements.yml` instructions touch the same section anyway.

## Risks / Trade-offs

- [Skip list rot — debt entries linger after their track lands] → Each entry names its track; the idiom-sweep change's tasks include deleting its entries, and specs make removal part of that change's definition of done.
- [ansible-lint/ansible-core version drift breaks CI spontaneously] → Pin the ansible-core and ansible-lint versions in the workflow; bump deliberately.
- [Dummy vault diverges from real vault keys, so syntax-check passes while real runs fail] → The dummy is generated from `vault/secrets.example.yaml` keys once modernize-safety lands, keeping the contract single-sourced.
- [yamllint fighting the repo's 2-space/inline style] → Config starts from `yamllint` default with line-length relaxed and truthy rules matched to existing style; style tightening belongs to the idiom sweep, not this change.

## Migration Plan

1. Land configs + workflow on the branch; iterate in CI until green.
2. Update README (correct playbook name, `ansible-galaxy install -r requirements.yml`, badge).
3. Rollback: delete the workflow file; nothing on hosts or in roles depends on it.

## Open Questions

- None blocking. Exact collection version ranges and pinned ansible-core version are implementation-time choices validated by the CI run itself.
