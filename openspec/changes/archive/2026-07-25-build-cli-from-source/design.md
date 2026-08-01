# Design: build-cli-from-source

## Context

Agave 4.1+ tarballs ship no `agave-validator` (verified against `v4.1.0-beta.3` assets), and `release.anza.xyz` 403s from some datacenter IPs. The repo already builds the Jito validator from source (`build-jito.sh`); this change makes the base CLI install source-built too, removing the CDN dependency entirely. Verified upstream facts: `scripts/cargo-install-all.sh` on the v4.1 branch supports `--no-build-validator-bins`; the `--validator-only` set is `agave-validator, agave-watchtower, solana-gossip, solana-genesis, solana-faucet` (no `solana`/`solana-keygen`); build lists live in `scripts/agave-build-lists.sh`.

## Goals / Non-Goals

**Goals:**
- Provisioning succeeds with no access to release.anza.xyz, on 4.1+ versions with no prebuilt validator.
- Idempotent re-runs; Jito symlink ownership respected; CLI always available via `active_release/bin`.

**Non-Goals:**
- Speeding up the build (sccache, prebuilt caches) — first-run cost is accepted.
- Changing the Jito build flow beyond the CLI-copy step.
- Binary verification/reproducible builds (worth a future change; today's flow has no checksum either).
- Supporting `solana_version: stable` (source build needs a concrete tag; the playbook always pins one).

## Decisions

1. **Clone shallow at the version tag** (`--depth 1 --branch v{{ solana_version }}`) into `{{ solana_home }}/build/agave` — not `/tmp` (build trees are multi-GB and `/tmp` may be small or `noexec`). The build dir is left in place after success; it makes re-builds after a version bump incremental-ish and is trivially removable. Alternative — build in ephemeral dir and delete — rejected: re-cloning + full rebuild on every version change with zero cache.
2. **Version bump handling**: the clone task re-clones when the checked-out tag differs from `v{{ solana_version }}` (compare `git describe --tags` output; `changed_when` accordingly). The build task's `creates:` guard keys on the *versioned* release path, so a bump naturally triggers a fresh build into a new `releases/<version>` dir.
3. **Jito mode splits build scope** (`--no-build-validator-bins` vs full). Building the validator twice on Jito hosts (~doubling a 30+ minute build) buys nothing — the Jito validator always wins the symlink. Non-Jito hosts need the validator from the vanilla build.
4. **Symlink create-only semantics** (`ln -s` guarded by a `stat`, or `file state=link` with a `when: not stat.exists`). The install flow must never fight `build-jito.sh` over `active_release`. First provision on a Jito host: symlink → vanilla CLI build (so `configure_node`'s `solana config set` works); after `build-jito.sh`: symlink → Jito build, and re-runs leave it alone.
5. **Outer guard moves to `active_release/bin/solana`.** The old guard (`agave-install` binary) is an artifact of the installer flow; `solana` is present in every layout this change produces (vanilla build, Jito build after CLI-copy).
6. **CLI-copy lives in `build-jito.sh`**, not in an Ansible task: the gap only exists the moment the Jito build re-points the symlink, and that happens under operator control outside Ansible. `cp -n` from `releases/{{ solana_version }}/solana-release/bin/` into the Jito release `bin/` — no-clobber so Jito-built binaries always win.
7. **Long build runs as a plain task, no `async`.** Ansible has no timeout on shell tasks by default; async adds failure modes (polling, orphaned jobs) for no benefit in a local-connection provisioning run. The task name states the expected duration so operators aren't surprised.

## Risks / Trade-offs

- [First provisioning run grows by 20–60+ min] → Documented in README and the task name; guards make it one-time.
- [Source build requires ~10 GB free in `{{ solana_home }}/build`] → Preflight assert on available space (df check) with a clear fail_msg, so it fails in seconds not after 40 minutes.
- [Rust toolchain version drift (agave pins its own toolchain)] → `cargo-install-all.sh` respects the repo's `rust-toolchain.toml` via rustup, which install_dev_tools provides; no extra handling needed.
- [`--no-build-validator-bins` flag could change across agave majors] → The flag exists on the v4.1 branch (verified); the task's failure would be loud, and the flag choice is centralized in one task.
- [crates.io/github.com also blocked on some hosts] → Out of scope; those hosts cannot build Jito today either — nothing regresses.

## Migration Plan

1. Land role changes + build-jito.sh update + README in one commit; CI (lint + syntax-check) validates statically — per project rule, no local `ansible-playbook` execution; real-host validation happens on the operator's next provisioning run.
2. Existing provisioned hosts: outer guard sees `active_release/bin/solana` → entire install flow skips; no host change.
3. Rollback: revert the commit; the old CDN flow returns (with its known 4.1+ limitations).

## Open Questions

- None blocking. Future follow-up: checksum/signature verification of the cloned tag (pin commit hashes per version) if supply-chain hardening becomes a priority.
