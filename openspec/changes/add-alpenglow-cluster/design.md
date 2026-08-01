# Design: add-alpenglow-cluster

## Context

Reference artifacts from a live alpenglow-testnet node (start script, build script, CLI config) define the target. Alpenglow differs from testnet/mainnet in: IP entrypoints, its own genesis/shred-version/bank-hash expectations, a different dynamic port range, alpenglow-only validator flags, no Jito, no known validators, and a validator built from an arbitrary agave ref rather than `v<semver>`.

## Goals / Non-Goals

**Goals:**
- `alpenglow` as a first-class wizard cluster; byte-identical output for the two existing clusters.
- The field node's exact flag set reproduced by template; volatile values prompted with warnings, never silently baked.
- Build path consistent with the Jito pattern (CLI from node-base, validator from an operator-run script).

**Non-Goals:**
- Alpenglow mainnet (doesn't exist; the cluster enum can grow again later).
- Auto-discovering current shred-version/bank-hash from the cluster (nice future addition; prompts + warnings for now).
- Jito-on-alpenglow (not a thing), DoubleZero on alpenglow (untested — stays default-off).

## Decisions

1. **Third start-script template**, not more conditionals in the existing two: the repo's variant-per-template pattern (standard vs jito) extends naturally, and alpenglow's flag set diverges enough (adds 5 flags, removes 4) that a shared template would be conditional soup. Selection in `setup_validator.yaml`: alpenglow > jito > standard.
2. **`dynamic_port_range` becomes a cluster preset + template token** (`@@DYNAMIC_PORT_RANGE@@`). Testnet/mainnet render the existing `8000-10000`, keeping the round-trip byte-identical; the firewall role's port-range split already consumes the variable, so iptables rules follow automatically.
2b. **`solana_version` becomes a cluster preset + template token** (`@@SOLANA_VERSION@@`, also feeding `watch_tower_version`): testnet/mainnet keep `4.1.0-beta.3` (byte-identical), alpenglow gets `4.2.0-beta.0` (tag verified upstream: `b23fc23b`) so node-base's CLI build matches the cluster's validator. `build-alpenglow.sh` defaults its ref to `v4.2.0-beta.0` with an override argument — the cluster moves faster than the repo, so the default is a stamped convenience, not a pin.
3. **Cluster flag in the playbook**: the template gains an `alpenglow.enabled` boolean (token-rendered) mirroring the `jito.enabled` pattern, driving template selection, assertions (`expected_shred_version`/`expected_bank_hash` required when true), and the node-base build-scope condition. Alternative — inferring from `cluster_environment` string — rejected: stringly-typed conditions scattered across roles.
4. **Shred version and bank hash are prompts with preset defaults**, asserted non-empty. They change on every cluster restart; baking them silently would generate confidently-wrong playbooks. The wizard warns at the prompt and again in next-steps.
5. **`build-alpenglow.sh` is a first-class sibling of `build-jito.sh`** (argbash-style single positional ref, package preflight, `--validator-only`, symlink flip), plus the lessons already learned there: no wholesale CLI copying, prints the `build-solana-cli.sh` hint when `solana` is absent from the release. Deployed only on alpenglow playbooks (`when: alpenglow.enabled`, like the jito script's guard).
6. **Metrics credentials are public cluster constants** (`ag` / `!d.tWEViQRhhP.*be9!a`) baked per cluster exactly like testnet/mainnet's — consistent with the established secrets policy (vault holds only `pager_duty_key`). The `!` characters need shell-quoting care only in docs; the template renders them into an env var string, not a shell context.
7. **Watchtower/alerting behave as on Jito hosts**: binary arrives with the alpenglow build (validator-only set includes it); the existing jito-aware skip extends its condition to alpenglow (no cargo attempt).

## Risks / Trade-offs

- [Alpenglow presets go stale fast (test cluster restarts)] → "Last verified" stamps, prompt + next-steps warnings, and the two most volatile values are operator-confirmed prompts, not silent presets.
- [`--full-rpc-api` on a voting validator is unusual for mainnet habits] → It matches the reference node and alpenglow's testing purpose; noted in the template comment.
- [Third cluster multiplies e2e matrix] → Alpenglow cases reuse the fake-disk hook and scripted inputs; round-trip guards pin the other clusters.
- [Firewall/port-range interactions] → The iptables role already derives rules from `dynamic_port_range`; e2e asserts the generated playbook carries the alpenglow range and the template token renders the legacy constant elsewhere.

## Migration Plan

1. Wizard + template + role changes in one commit; regenerate sample (must be byte-identical); alpenglow e2e generation checks; CI.
2. Existing hosts unaffected; alpenglow bootstrap = wizard → disk-setup → playbook → `build-alpenglow.sh <ref>` → `build-solana-cli.sh` → start validator.
3. Rollback: revert; the two-cluster wizard returns.

## Open Questions

- None blocking. The current alpenglow agave ref is operator-supplied at build time (the cluster's coordination channel publishes it), so the repo never pins it.
