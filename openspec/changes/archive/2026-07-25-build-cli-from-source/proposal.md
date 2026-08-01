# Proposal: build-cli-from-source

## Why

Two independent failures broke the prebuilt install path in production: (1) starting with the agave 4.1 line, release tarballs no longer contain `agave-validator` — Anza expects validator operators to build from source (verified by listing the `v4.1.0-beta.3` tarball: CLI tools only); (2) `release.anza.xyz` is CDN-blocked from some datacenter IPs (observed 403 from a Latitude.sh host), so even the CLI installer download can fail. Building from source in the provisioning flow fixes both: no dependency on the blocked CDN, and a validator binary that actually exists on 4.1+.

## What Changes

- **Reorder `roles/node-base/tasks/main.yaml`**: `install_dev_tools` (build packages + Rust) moves before the CLI install, since the source build needs them.
- **Rewrite `roles/node-base/tasks/install_solana_client.yaml`** to build from source instead of downloading the CDN installer:
  - `git clone --depth 1 --branch v{{ solana_version }} https://github.com/anza-xyz/agave.git` into a build dir under `{{ solana_home }}`.
  - Run `scripts/cargo-install-all.sh` into `~/.local/share/solana/install/releases/{{ solana_version }}/solana-release` — with `--no-build-validator-bins` when `jito.enabled` (the Jito build supplies the validator), full build otherwise.
  - Create the `active_release` symlink only if one does not already exist (never steals the symlink from a Jito build on re-runs).
  - Guarded by `creates:` on the built `bin/solana`, so re-runs skip the build.
- **Change the outer guard in `main.yaml`** from `stat` on `agave-install` to `stat` on `active_release/bin/solana` (always produced by the build; `agave-install` is a prebuilt-flow artifact).
- **Extend `roles/validator/files/build-jito.sh`**: after installing the Jito build and re-pointing `active_release`, copy the CLI binaries (`cp -n`) from the vanilla release dir into the Jito release `bin/` — the Jito `--validator-only` build lacks `solana`/`solana-keygen`, which the repo's scripts and monitoring require.
- **README**: document that 4.1+ provisioning builds from source (first run takes 20–60+ minutes on the CLI build, plus the Jito build; requires ~10 GB free for the build tree), and remove/replace the prebuilt-installer wording.
- **BREAKING (flow, not host state)**: the CDN download path is removed; hosts that already have an `active_release` are untouched (guard skips everything).

## Capabilities

### New Capabilities

- `agave-source-install`: the install contract — where sources are cloned, which build flags apply per Jito mode, the release/symlink layout, idempotency guards, and the CLI-completeness guarantee for Jito builds.

### Modified Capabilities

<!-- none — no existing spec covers the node-base install flow -->

## Impact

- `roles/node-base/tasks/main.yaml`, `install_solana_client.yaml` — rewritten flow.
- `roles/validator/files/build-jito.sh` — CLI copy step.
- `README.md` — install documentation.
- First provisioning run becomes significantly longer (compilation); subsequent runs are unaffected (guards skip).
- Requires outbound access to github.com and crates.io (already required by rustup/cargo in the existing flow); drops the `release.anza.xyz` dependency entirely.
