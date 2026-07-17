# Tasks: wizard-manual-disk

## 1. Template tokenization (output-neutral)

- [ ] 1.1 In `playbooks/templates/profile.yaml.tmpl`, replace `mount: True` and `config: True` under `disk_management` with `@@DISK_MOUNT@@`/`@@DISK_CONFIG@@`
- [ ] 1.2 In `bin/new-playbook.sh`, wire the two tokens into the awk pass; automated layouts substitute `True`/`True`

## 2. Wizard manual mode

- [ ] 2.1 Extend the disk layout prompt to `separate`/`single`/`manual` (re-prompt on invalid); `manual` asks a follow-up shape prompt (`single`/`separate`) then the corresponding device prompt(s), reusing the existing branches
- [ ] 2.2 Manual mode sets `DISK_MOUNT=False`, `DISK_CONFIG=True`; disks block and paths identical to the chosen shape's automated output
- [ ] 2.3 Add the setup-command renderer: per disk — `mkfs.xfs` (no `-f`), `mkdir -p` mount dir, `mount -o $DISK_FS_OPTIONS`, UUID fstab append (grep-guarded, idempotent), then `mount -a` + `findmnt` verification; sourced from the same `DISK_FS_OPTIONS` constant as the disks block
- [ ] 2.4 Write the commands to `playbooks/disk-setup-<name>.sh` (header naming the target playbook, `--yes` guard that prints-and-exits-1 without the flag, `lsblk` echo of target devices before formatting) and print the same commands to the terminal after generation
- [ ] 2.5 Add `playbooks/disk-setup-*.sh` to `.gitignore`

## 3. Docs

- [ ] 3.1 README: document the `manual` layout — when to use it, what the playbook does/doesn't do (`mount: False, config: True`), where the setup script lands, that it's gitignored and regenerable, and the `--yes` guard

## 4. Verification

- [ ] 4.1 Round-trip: regenerate `playbooks/sample-testnet-profile.yaml` (separate, same inputs) — empty diff required
- [ ] 4.2 Scripted e2e, manual single: playbook parses with `mount: False, config: True`, shared-device entries, `/mnt/solana/*` paths; `disk-setup-<name>.sh` exists, contains the same device/mount-dir/options values as the playbook, and running it without `--yes` prints commands and exits non-zero (safe to execute on the dev box — the guard means nothing runs)
- [ ] 4.3 Scripted e2e, manual separate + invalid layout value re-prompt; automated single/separate outputs byte-identical to pre-change (compare against a pre-change generation)
- [ ] 4.4 shellcheck on `bin/new-playbook.sh` and on a generated `disk-setup-*.sh` specimen; yamllint + pinned ansible-lint clean; commit, push, CI green
