# Tasks: storage-paths-only

## 1. Template and sample

- [ ] 1.1 Remove the `disk_management` and `ramdisk_management` blocks from `playbooks/templates/profile.yaml.tmpl` (drops `@@DISK_MANAGEMENT_DISKS@@`, `@@DISK_MOUNT@@`, `@@DISK_CONFIG@@` tokens); keep the three path tokens

## 2. Wizard

- [ ] 2.1 Remove the automated/manual question and `DISK_MOUNT`/`DISK_CONFIG`/`MANUAL_SETUP` plumbing; the disk flow (assignment or classic prompts) always generates `disk-setup-<name>.sh` and always prints the run-before-playbook instruction in next-steps
- [ ] 2.2 Remove the disks-block renderer (`render_disks_block`, `disk_entry`) and the classic `manual` layout option (separate/single remain); drop the now-unused awk vars/gsubs
- [ ] 2.3 Regenerate the sample — verify it contains no `disk_management`/`ramdisk_management` and no device paths

## 3. Validator role

- [ ] 3.1 Replace `disks_mount.yaml` and `ramdisk.yaml` with `storage_dirs.yaml`: mountpoint warning per path (findmnt on the mount dir, warn naming the disk-setup script, never fail) + create the three path dirs with solana ownership; update `main.yaml` imports
- [ ] 3.2 Repo sweep: no remaining references to `disk_management`/`ramdisk_management` (roles, defaults, playbook assertions, docs)

## 4. Docs

- [ ] 4.1 README: BREAKING note — Ansible no longer formats/mounts; disk-setup script runs first; ramdisk removed

## 5. Verification

- [ ] 5.1 e2e: separate, single, and hybrid-assignment generations — playbooks parse, contain paths only, setup scripts cover the right devices/mount dirs; `--yes` guard intact
- [ ] 5.2 Static review of `storage_dirs.yaml` against the host-storage-preparation spec scenarios
- [ ] 5.3 shellcheck + yamllint (+ pinned ansible-lint if available) clean; commit, push, CI green