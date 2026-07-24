[![CI](https://github.com/jaguar-labs/jaguar-node-oss/actions/workflows/ci.yaml/badge.svg)](https://github.com/jaguar-labs/jaguar-node-oss/actions/workflows/ci.yaml)

### Quick Start
This setup not include nvme disk setup. It lease the nvme disk setup to the operators.
> **_NOTE:_**  Tested on Ubuntu 22.04 and 24.04.

1. clone the repo and cd into the directory
```bash
git clone https://github.com/jaguar-labs/jaguar-node-oss.git
```
2. Install ansible
```bash
sudo apt install ansible
```
3. Install the required Ansible collections
```bash
ansible-galaxy collection install -r requirements.yml
```
4. Create a validator profile with the wizard. It prompts for ~10 validator-specific values (name, cluster, pubkeys, disk devices, log path, Jito/XDP toggles), auto-fills cluster presets (entrypoints, known validators, genesis hash, Jito endpoints), and writes `playbooks/<name>-<cluster>-profile.yaml`. No keys yet? Answer `gen` at the identity prompt and `skip` at the vote account prompt — the playbook generates both keypairs on the host during provisioning and fills the pubkeys automatically; the one manual step left is creating the vote account on-chain (`solana create-vote-account`, printed in the wizard's next-steps; watchtower alerts until it exists — expected during bootstrap):
```bash
bin/new-playbook.sh          # refuses to overwrite an existing profile; use --force to regenerate
```
The canonical profile source is `playbooks/templates/profile.yaml.tmpl` — `playbooks/sample-testnet-profile.yaml` is generated from it. If `vault/secrets.yaml` is missing, the wizard offers to create it (secret values prompted with hidden input and encrypted immediately; step 5 below covers the manual route).

When the wizard detects unused disks (bare devices: no partitions, no filesystem, unmounted), it lists them numbered and asks which to select (numbers or device paths, `all`, or `none` to use the classic prompts instead). Each selected disk then gets a role question: `ledger`, `accounts`, `snapshots` (comma-separated for sharing) or `all` — every role must land on exactly one disk (duplicates and gaps re-prompt). Hybrid mappings work: e.g. ledger alone on one NVMe (`/mnt/solana_ledger`) with accounts+snapshots sharing another (`/mnt/solana_accounts_snapshots`). Afterwards you choose whether the playbook formats/mounts the disks, or you prepare them yourself (which also generates the `disk-setup-<name>.sh` commands for exactly the assigned disks).

Declining the offer (or having no bare disks) falls back to the classic disk layout prompt with three modes: `separate` (one NVMe each for ledger/accounts/snapshots — formatted and mounted by the playbook), `single` (everything on one disk), and `manual` (you format and mount the disk(s) yourself). In manual mode the generated playbook sets `disk_management.mount: False, config: True` — the role never touches your filesystems but still creates the ledger/accounts/snapshots subdirs with `solana` ownership — and the wizard prints the exact `mkfs`/`mount`/fstab commands for your devices, also saving them to `playbooks/disk-setup-<name>.sh` (gitignored; regenerate by re-running the wizard). The script is a dry run unless invoked with `--yes`, and its `mkfs.xfs` has no `-f`, so an already-formatted disk fails loudly instead of being wiped.
5. Create your secrets vault. Secrets (telegraf credentials, PagerDuty key, Solana metrics credential) are never stored in plaintext in this repo — they live in an Ansible Vault encrypted file:
```bash
cp vault/secrets.example.yaml vault/secrets.yaml
# edit vault/secrets.yaml and fill in real values
ansible-vault encrypt vault/secrets.yaml
```
6. Edit and Run the following command to install the full validator profile
```bash
ansible-playbook playbooks/sample-testnet-profile.yaml -i inventory -e host=local --connection=local --ask-vault-pass
```
Use `--vault-password-file <path>` instead of `--ask-vault-pass` for unattended runs (keep the password file outside the repo; `*.vault-pass*` is gitignored).

> **_BUILD NOTE:_** Agave is **built from source** during provisioning (agave 4.1+ ships no prebuilt validator binary, and the release CDN is blocked from some datacenter networks — only github.com and crates.io are needed). The first run adds 20–60+ minutes of compilation and needs ~10 GB free in the solana home. On Jito-enabled profiles the playbook builds the CLI tools only; the validator itself is built by running `~/build-jito.sh` as the `solana` user afterwards (it also copies the CLI tools into the Jito release so `solana`/`solana-keygen` stay available). Re-runs skip all build steps.

> **_SECURITY NOTE:_** The `solana_metrics_*` values (public Anza per-cluster write credentials) and the `telegraf_*` credentials (shared community metrics-backend values) ship as plaintext defaults — override them via the vault if your backends use private credentials. The one genuinely private secret you must set is your PagerDuty key, which lives only in the encrypted vault.