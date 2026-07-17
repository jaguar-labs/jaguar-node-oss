# Tasks: wizard-single-disk

## 1. Template refactor (output-neutral)

- [x] 1.1 Replace the fixed three-disk block in `playbooks/templates/profile.yaml.tmpl` with `@@DISK_MANAGEMENT_DISKS@@` and the three path values with `@@LEDGER_PATH@@`/`@@ACCOUNTS_PATH@@`/`@@SNAPSHOTS_PATH@@` (drop the now-unused `@@*_DEV@@` scalar tokens)
- [x] 1.2 In `bin/new-playbook.sh`, add a separate-layout disk-block renderer producing byte-identical output to the old inline block, and wire the new tokens into the awk pass

## 2. Wizard prompt + single-disk rendering

- [x] 2.1 Add the disk layout prompt (`separate`/`single`, default `separate`, re-prompt on invalid) after the pubkey prompts; `separate` keeps the existing three device prompts, `single` prompts for one device (default `/dev/nvme0n1`)
- [x] 2.2 Add the single-layout renderer: three entries sharing dev + `mount_dir: /mnt/solana` with distinct subdir/startup_arg, a YAML comment explaining the shared-device idempotency, and path derivation (`/mnt/solana/{ledger,accounts,snapshots}`)
- [x] 2.3 Print a one-line note when `single` is chosen on mainnet that separate NVMes are recommended

## 3. Utility script path fixes

- [x] 3.1 `roles/validator/templates/dl-snapshots.sh.j2`: `DEFAULT_OUTPUT_DIR="{{ snapshots_path }}"`
- [x] 3.2 `roles/validator/templates/node-transition.sh.j2`: replace the hardcoded `/mnt/solana_ledger/ledger` tower-file check (and its message text) with `{{ ledger_path }}`

## 4. Verification

- [x] 4.1 Regenerate `playbooks/sample-testnet-profile.yaml` (separate layout, same inputs as before) and require an empty git diff — proves the template refactor is output-neutral
- [x] 4.2 Scripted e2e: single-layout testnet run — assert the generated playbook parses, the three disks entries share `/mnt/solana` + device, paths point under `/mnt/solana/`, and no `@@` tokens remain
- [x] 4.3 Scripted e2e: layout prompt validation (invalid value re-prompts), and separate layout with custom devices still lands them in the right entries
- [ ] 4.4 shellcheck clean; yamllint + pinned ansible-lint clean; commit and push; confirm CI green
