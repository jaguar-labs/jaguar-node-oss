# Tasks: build-cli-from-source

## 1. Reorder and re-guard node-base

- [x] 1.1 In `roles/node-base/tasks/main.yaml`, move the `install_dev_tools` import before the CLI install block (build deps + Rust must exist first)
- [x] 1.2 Change the outer guard stat from `.../active_release/bin/agave-install` to `.../active_release/bin/solana` (and use `{{ solana_home }}` instead of the hardcoded `/home/solana`)

## 2. Source-build install task

- [x] 2.1 Rewrite `roles/node-base/tasks/install_solana_client.yaml`: preflight free-space assert (≥ 10 GB in `{{ solana_home }}`) with clear fail_msg
- [x] 2.2 Shallow-clone `anza-xyz/agave` at `v{{ solana_version }}` into `{{ solana_home }}/build/agave` as `{{ solana_user }}`; re-clone when the checked-out tag differs from the requested version (`changed_when` on tag comparison)
- [x] 2.3 Build task: `scripts/cargo-install-all.sh` into `releases/{{ solana_version }}/solana-release`, `--no-build-validator-bins` when `jito.enabled | bool`, full build otherwise; `creates:` guard on the built `bin/solana`; task name states the 20–60+ min expectation; sources `~/.cargo/env`
- [x] 2.4 Create the `active_release` symlink only when none exists (stat + `when`); never re-point an existing link
- [x] 2.5 Remove the CDN download/installer tasks and the `/tmp/solana` cleanup

## 3. Jito CLI completeness

- [x] 3.1 In `roles/validator/files/build-jito.sh`, after the `active_release` re-point: `cp -n` all binaries from `$HOME/.local/share/solana/install/releases/<solana_version>/solana-release/bin/` into the Jito release `bin/` (no-clobber so Jito-built binaries win; warn and continue if the vanilla release dir is absent)
- [x] 3.2 Ensure build-jito.sh knows the vanilla version dir: derive it from the jito tag (strip the `-jito` suffix) or accept it as an optional second argument

## 4. Docs

- [x] 4.1 README: replace prebuilt-installer wording — 4.1+ provisioning builds agave from source (github.com + crates.io only, no release.anza.xyz), first run adds 20–60+ min and needs ~10 GB free; note the Jito flow (`build-jito.sh` builds the validator, node-base builds the CLI)

## 5. Verification (static + CI; no local ansible runs)

- [x] 5.1 Static review: task-by-task dry read of the new install flow against the four spec requirements (source-only install, jito build scope, idempotency/symlink safety, CLI completeness)
- [x] 5.2 shellcheck on the updated `build-jito.sh`; yamllint + pinned ansible-lint clean
- [x] 5.3 Verify the clone tag exists upstream for the current pinned version (`git ls-remote` check for `v4.1.0-beta.3`) and that `--no-build-validator-bins` is present in that tag's `cargo-install-all.sh`
- [ ] 5.4 Commit, push, confirm CI green; flag to the operator that the next real provisioning run validates the build end-to-end
