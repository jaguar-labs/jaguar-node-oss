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
4. Create a validator profile with the wizard. It prompts for ~10 validator-specific values (name, cluster, pubkeys, disk devices, log path, Jito/XDP toggles), auto-fills cluster presets (entrypoints, known validators, genesis hash, Jito endpoints), and writes `playbooks/<name>-<cluster>-profile.yaml`:
```bash
bin/new-playbook.sh          # refuses to overwrite an existing profile; use --force to regenerate
```
The canonical profile source is `playbooks/templates/profile.yaml.tmpl` — `playbooks/sample-testnet-profile.yaml` is generated from it. If `vault/secrets.yaml` is missing, the wizard offers to create it (secret values prompted with hidden input and encrypted immediately; step 5 below covers the manual route).
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

> **_SECURITY NOTE:_** Earlier revisions of this repository committed a telegraf password in plaintext — rotate it before reusing this automation. The `solana_metrics_*` values are the public per-cluster write credentials from the Anza docs (defaults are pre-filled in the example); the private secrets you must set are the telegraf credentials and your PagerDuty key.