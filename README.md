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
4. Create your secrets vault. Secrets (telegraf credentials, PagerDuty key, Solana metrics credential) are never stored in plaintext in this repo — they live in an Ansible Vault encrypted file:
```bash
cp vault/secrets.example.yaml vault/secrets.yaml
# edit vault/secrets.yaml and fill in real values
ansible-vault encrypt vault/secrets.yaml
```
5. Edit and Run the following command to install the full validator profile
```bash
ansible-playbook playbooks/sample-testnet-profile.yaml -i inventory -e host=local --connection=local --ask-vault-pass
```
Use `--vault-password-file <path>` instead of `--ask-vault-pass` for unattended runs (keep the password file outside the repo; `*.vault-pass*` is gitignored).

> **_SECURITY NOTE:_** Earlier revisions of this repository committed a Solana metrics write credential (`solana_metrics_url`) and a telegraf password in plaintext. Treat those values as compromised: rotate the metrics write credential and the telegraf password before reusing this automation. The values now live only in your encrypted vault.