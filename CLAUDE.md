# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible automation for provisioning **Solana validator and RPC nodes** with optional Jito MEV integration. Targets Ubuntu 22.04. Uses `agave-validator` (Anza fork), not the legacy `solana-validator`.

## Commands

```bash
# Install required collection
ansible-galaxy collection install community.general

# Run a playbook locally
ansible-playbook playbooks/<profile>.yaml -i inventory -e host=local --connection=local

# Syntax check a playbook
ansible-playbook playbooks/<profile>.yaml --syntax-check

# List tasks in a playbook
ansible-playbook playbooks/<profile>.yaml --list-tasks

# Dry run
ansible-playbook playbooks/<profile>.yaml -i inventory -e host=local --connection=local --check
```

## Architecture

**Roles execute in order**: system-optimization → common → node-base → validator → alerting → monitoring. The `rpc` role is a standalone alternative.

### Role Responsibilities

- **system-optimization**: Tuned profile, CPU isolation for PoH thread, kernel parameters
- **common**: Packages, firewall (iptables), fail2ban, sysctl tuning, chrony NTP, solana user creation
- **node-base**: Solana CLI install (via `agave-install`), systemd service, logrotate, keypair setup
- **validator**: Startup script generation (Jito vs non-Jito), disk/ramdisk mounts, utility scripts (node-transition, pin-poh, dl-snapshots)
- **rpc**: Non-voting RPC node startup script (`--no-voting --full-rpc-api`)
- **monitoring**: Telegraf + custom Python monitoring library, InfluxDB/TimescaleDB backends
- **alerting**: `agave-watchtower` with PagerDuty integration

### Key Patterns

- **Jito conditional**: `jito.enabled` boolean controls Jito-specific tasks, templates, and firewall rules throughout. Two separate startup script templates: `start-node.sh.j2` (standard) and `start-node-jito.sh.j2` (Jito-enabled).
- **Symlink identity switching**: `validator-keypair.json` symlinks to either `funded-validator-keypair.json` or `unfunded-validator-keypair.json` for voting/non-voting transitions.
- **Variable layering**: Role `defaults/main.yaml` < playbook `vars` < CLI `-e` overrides.
- **Port range transform**: `dynamic_port_range` ("8000-10000") is split and reformatted to "8000:10000" for iptables rules via `set_fact`.

### Shared Variables Across Roles

`solana_user`, `solana_home`, `secrets_path`, `ledger_path`, `accounts_path`, `snapshots_path`, `cluster_rpc_address`, `rpc_port`, `dynamic_port_range`, `cluster_environment`, `vote_account_pubkey`, `expected_genesis_hash`.

### On-Host File Layout

- `/home/solana/` — home directory, startup scripts
- `/home/solana/.secrets/` — keypairs (0700 permissions)
- `/home/solana/monitoring/` — Python venv + monitoring scripts
- `/home/solana/.local/share/solana/install/active_release/bin/` — Solana CLI binaries
- Storage paths are configurable via `disk_management` / `ramdisk_management` vars

## Conventions

- Task files use `.yaml` extension (not `.yml`), except `defaults/main.yml` in the validator role which uses `.yml`
- Templates use `.j2` extension for Jinja2
- Playbooks define all variables inline under `vars:` with pre-task assertions for required values
- Handlers are defined in `roles/<role>/handlers/main.yaml`
- Python monitoring files live in `roles/monitoring/files/` and are copied (not templated) to hosts
