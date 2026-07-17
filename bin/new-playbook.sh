#!/usr/bin/env bash
# shellcheck disable=SC2034  # preset_* vars are read via indirect expansion in p()
# new-playbook.sh — interactive wizard that generates a validator playbook from
# playbooks/templates/profile.yaml.tmpl, filling validator-specific values and
# cluster presets. Never runs ansible-playbook; CI validates generated output.
#
# Usage: bin/new-playbook.sh [--force] [--help]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$REPO_ROOT/playbooks/templates/profile.yaml.tmpl"
EXAMPLE_VAULT="$REPO_ROOT/vault/secrets.example.yaml"
VAULT_FILE="$REPO_ROOT/vault/secrets.yaml"

FORCE=0
OUTPUT_FILE=""
VAULT_PLAINTEXT_PENDING=0

usage() {
  sed -n '3,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

cleanup() {
  status=$?
  stty echo 2>/dev/null || true
  if [ -n "$OUTPUT_FILE" ] && [ "$status" -ne 0 ] && [ -f "$OUTPUT_FILE" ]; then
    rm -f "$OUTPUT_FILE"
    echo "Aborted: removed partial output $OUTPUT_FILE." >&2
  fi
  if [ "$VAULT_PLAINTEXT_PENDING" -eq 1 ] && [ -f "$VAULT_FILE" ]; then
    rm -f "$VAULT_FILE"
    echo "Aborted: removed unencrypted $VAULT_FILE — nothing was saved." >&2
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --help|-h) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
  shift
done

[ -f "$TEMPLATE" ] || { echo "Template not found: $TEMPLATE" >&2; exit 1; }

# ---------------------------------------------------------------- cluster presets
# Last verified: 2026-07 (testnet: repo sample profile; mainnet: Anza docs +
# roles/validator/defaults/main.yml jito block). Review before mainnet use.
# shellcheck disable=SC2034  # preset_* vars are read via indirect expansion in p()
preset_testnet_genesis="4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY"
preset_testnet_remote_rpc="https://api.testnet.solana.com"
preset_testnet_metrics_db="tds"
preset_testnet_entrypoints="entrypoint.testnet.solana.com:8001 entrypoint2.testnet.solana.com:8001 entrypoint3.testnet.solana.com:8001"
preset_testnet_known_validators="5D1fNXzvv5NjV1ysLjirC4WY92RNsVH18vjmcszZd8on dDzy5SR3AXdYWVqbDEkVFdvSPCtS9ihF5kJkHCtXoFs Ft5fbkqNa76vnsjYNwjDZUXoTWpP7VYm3mtsaQckQADN eoKpUABi59aT4rR9HGS3LcMecfut9x7zJyodWWP43YQ 9QxCLckBiJc783jnMvXZubK4wH86Eqqvashtrwvcsgkv"
preset_testnet_jito_tip_payment="GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
preset_testnet_jito_tip_distribution="DzvGET57TAgEDxvm3ERUM4GNcsAJdqjDLCne9sdfY4wf"
preset_testnet_jito_merkle_auth="7T4inmPmtNBX3MhLwJ9hFsSMnGJYYkKioVABSNTWVRuS"
preset_testnet_jito_shred_receiver="64.130.35.224:1002"
preset_testnet_jito_regions="ny dallas"
preset_testnet_jito_ntp="ntp.dallas.jito.wtf"

preset_mainnet_genesis="5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
preset_mainnet_remote_rpc="https://api.mainnet-beta.solana.com"
preset_mainnet_metrics_db="mainnet-beta"
preset_mainnet_entrypoints="entrypoint.mainnet-beta.solana.com:8001 entrypoint2.mainnet-beta.solana.com:8001 entrypoint3.mainnet-beta.solana.com:8001"
preset_mainnet_known_validators="7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2 GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S"
preset_mainnet_jito_tip_payment="T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt"
preset_mainnet_jito_tip_distribution="4R3gSG8BpU4t19KYj8CfnbtRpnT8gtk4dvTHxVRwc2r7"
preset_mainnet_jito_merkle_auth="GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib"
preset_mainnet_jito_shred_receiver="141.98.216.96:1002"
preset_mainnet_jito_regions="ny amsterdam dublin frankfurt london slc singapore tokyo"
preset_mainnet_jito_ntp="ntp.dallas.jito.wtf"

# ---------------------------------------------------------------- prompt helpers
# Read from the terminal when there is one, else stdin (enables scripted testing).
if { exec 3</dev/tty; } 2>/dev/null; then :; else exec 3<&0; fi

prompt() { # prompt <question> <default> -> REPLY
  local q="$1" d="${2-}"
  if [ -n "$d" ]; then
    read -u 3 -rp "$q [$d]: " REPLY
    REPLY="${REPLY:-$d}"
  else
    read -u 3 -rp "$q: " REPLY
  fi
}

prompt_yn() { # prompt_yn <question> <default y|n> -> 0=yes 1=no
  local ans
  while :; do
    prompt "$1 (y/n)" "$2"; ans="${REPLY,,}"
    case "$ans" in y|yes) return 0 ;; n|no) return 1 ;; esac
    echo "  Please answer y or n."
  done
}

prompt_valid() { # prompt_valid <question> <default> <regex> <error> -> REPLY
  while :; do
    prompt "$1" "$2"
    [[ "$REPLY" =~ $3 ]] && return 0
    echo "  Invalid: $4"
  done
}

RE_SLUG='^[a-z0-9][a-z0-9-]{0,40}$'
RE_PUBKEY='^[1-9A-HJ-NP-Za-km-z]{32,44}$'
RE_DEV='^/dev/[a-zA-Z0-9/_-]+$'
RE_ABSPATH='^/[a-zA-Z0-9/._-]+$'
RE_CORES='^[0-9]+(,[0-9]+)*$'
RE_BPS='^[0-9]{1,4}$'
RE_IFACE='^[a-zA-Z0-9._-]+$'

# ---------------------------------------------------------------- essential prompts
echo "== jaguar-node playbook wizard =="
echo "Enter accepts the [default]. Ctrl-C aborts safely."
echo

prompt_valid "Validator name (slug, used in filename and metrics)" "" "$RE_SLUG" "lowercase letters, digits, dashes (max 41 chars)"
VALIDATOR_NAME="$REPLY"

while :; do
  prompt "Cluster (testnet/mainnet)" "testnet"
  case "$REPLY" in testnet|mainnet) CLUSTER="$REPLY"; break ;; *) echo "  Invalid: must be testnet or mainnet" ;; esac
done

prompt_valid "Validator identity pubkey" "" "$RE_PUBKEY" "must be base58, 32-44 chars"
IDENTITY_PUBKEY="$REPLY"
prompt_valid "Vote account pubkey" "" "$RE_PUBKEY" "must be base58, 32-44 chars"
VOTE_PUBKEY="$REPLY"

prompt_valid "Ledger disk device" "/dev/nvme0n1" "$RE_DEV" "must look like /dev/..."
LEDGER_DEV="$REPLY"
prompt_valid "Accounts disk device" "/dev/nvme1n1" "$RE_DEV" "must look like /dev/..."
ACCOUNTS_DEV="$REPLY"
prompt_valid "Snapshots disk device" "/dev/nvme4n1" "$RE_DEV" "must look like /dev/..."
SNAPSHOTS_DEV="$REPLY"

prompt_valid "Validator log path" "/mnt/solana/log" "$RE_ABSPATH" "must be an absolute path"
LOG_PATH="$REPLY"

# cluster presets (indirect expansion off the chosen cluster)
p() { local v="preset_${CLUSTER}_$1"; printf '%s' "${!v}"; }

if prompt_yn "Enable Jito MEV?" "y"; then
  JITO_ENABLED="True"
  default_bps=0; [ "$CLUSTER" = "mainnet" ] && default_bps=800
  prompt_valid "Jito commission (bps)" "$default_bps" "$RE_BPS" "0-9999"
  JITO_COMMISSION_BPS="$REPLY"
  while :; do
    prompt "Jito block-engine region ($(p jito_regions | tr ' ' '/'))" "ny"
    case " $(p jito_regions) " in *" $REPLY "*) JITO_REGION="$REPLY"; break ;; esac
    echo "  Invalid: must be one of: $(p jito_regions)"
  done
  case "$CLUSTER" in
    testnet) JITO_BLOCK_ENGINE_URL="https://${JITO_REGION}.testnet.block-engine.jito.wtf" ;;
    mainnet) JITO_BLOCK_ENGINE_URL="https://${JITO_REGION}.mainnet.block-engine.jito.wtf" ;;
  esac
  if [ "$JITO_REGION" != "ny" ]; then
    echo "  NOTE: shred_receiver_address preset is the NY endpoint; adjust it in the"
    echo "  generated playbook for region '$JITO_REGION' (see Jito docs)."
  fi
else
  JITO_ENABLED="False"
  JITO_COMMISSION_BPS="0"
  JITO_BLOCK_ENGINE_URL=""
fi

if prompt_yn "Enable XDP retransmit?" "n"; then
  XDP_ENABLED="true"
  prompt_valid "XDP NIC interface (bond MEMBER if bonded)" "" "$RE_IFACE" "interface name"
  XDP_INTERFACE="$REPLY"
  prompt_valid "XDP retransmit CPU cores (comma-separated)" "1" "$RE_CORES" "e.g. 1 or 1,3"
  XDP_RETRANSMIT_CORES="$REPLY"
else
  XDP_ENABLED="false"
  XDP_INTERFACE=""
  XDP_RETRANSMIT_CORES="1"
fi

# ---------------------------------------------------------------- generation
OUTPUT_FILE="$REPO_ROOT/playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml"
if [ -e "$OUTPUT_FILE" ] && [ "$FORCE" -ne 1 ]; then
  OUTPUT_FILE=""  # don't let cleanup touch it
  echo "Refusing to overwrite existing $REPO_ROOT/playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml (re-run with --force)." >&2
  exit 1
fi

yaml_list_block() { # yaml_list_block <space separated items> -> 6-space indented "- item" lines
  local out="" item
  for item in $1; do out+="      - ${item}"$'\n'; done
  printf '%s' "${out%$'\n'}"
}

ENTRYPOINTS_BLOCK="$(yaml_list_block "$(p entrypoints)")"
KNOWN_VALIDATORS_BLOCK="$(yaml_list_block "$(p known_validators)")"

awk \
  -v VALIDATOR_NAME="$VALIDATOR_NAME" \
  -v CLUSTER="$CLUSTER" \
  -v IDENTITY_PUBKEY="$IDENTITY_PUBKEY" \
  -v VOTE_PUBKEY="$VOTE_PUBKEY" \
  -v LEDGER_DEV="$LEDGER_DEV" \
  -v ACCOUNTS_DEV="$ACCOUNTS_DEV" \
  -v SNAPSHOTS_DEV="$SNAPSHOTS_DEV" \
  -v LOG_PATH="$LOG_PATH" \
  -v GENESIS_HASH="$(p genesis)" \
  -v REMOTE_RPC="$(p remote_rpc)" \
  -v METRICS_DB="$(p metrics_db)" \
  -v ENTRYPOINTS_BLOCK="$ENTRYPOINTS_BLOCK" \
  -v KNOWN_VALIDATORS_BLOCK="$KNOWN_VALIDATORS_BLOCK" \
  -v JITO_ENABLED="$JITO_ENABLED" \
  -v JITO_TIP_PAYMENT="$(p jito_tip_payment)" \
  -v JITO_TIP_DISTRIBUTION="$(p jito_tip_distribution)" \
  -v JITO_MERKLE_AUTH="$(p jito_merkle_auth)" \
  -v JITO_COMMISSION_BPS="$JITO_COMMISSION_BPS" \
  -v JITO_BLOCK_ENGINE_URL="$JITO_BLOCK_ENGINE_URL" \
  -v JITO_SHRED_RECEIVER="$(p jito_shred_receiver)" \
  -v JITO_NTP="$(p jito_ntp)" \
  -v XDP_ENABLED="$XDP_ENABLED" \
  -v XDP_INTERFACE="$XDP_INTERFACE" \
  -v XDP_RETRANSMIT_CORES="$XDP_RETRANSMIT_CORES" \
  '
  # skip the template self-description header (lines 1-4 starting with "#")
  NR <= 4 && /^#/ { next }
  {
    line = $0
    gsub(/@@VALIDATOR_NAME@@/, VALIDATOR_NAME, line)
    gsub(/@@CLUSTER@@/, CLUSTER, line)
    gsub(/@@IDENTITY_PUBKEY@@/, IDENTITY_PUBKEY, line)
    gsub(/@@VOTE_PUBKEY@@/, VOTE_PUBKEY, line)
    gsub(/@@LEDGER_DEV@@/, LEDGER_DEV, line)
    gsub(/@@ACCOUNTS_DEV@@/, ACCOUNTS_DEV, line)
    gsub(/@@SNAPSHOTS_DEV@@/, SNAPSHOTS_DEV, line)
    gsub(/@@LOG_PATH@@/, LOG_PATH, line)
    gsub(/@@GENESIS_HASH@@/, GENESIS_HASH, line)
    gsub(/@@REMOTE_RPC@@/, REMOTE_RPC, line)
    gsub(/@@METRICS_DB@@/, METRICS_DB, line)
    gsub(/@@JITO_ENABLED@@/, JITO_ENABLED, line)
    gsub(/@@JITO_TIP_PAYMENT@@/, JITO_TIP_PAYMENT, line)
    gsub(/@@JITO_TIP_DISTRIBUTION@@/, JITO_TIP_DISTRIBUTION, line)
    gsub(/@@JITO_MERKLE_AUTH@@/, JITO_MERKLE_AUTH, line)
    gsub(/@@JITO_COMMISSION_BPS@@/, JITO_COMMISSION_BPS, line)
    gsub(/@@JITO_BLOCK_ENGINE_URL@@/, JITO_BLOCK_ENGINE_URL, line)
    gsub(/@@JITO_SHRED_RECEIVER@@/, JITO_SHRED_RECEIVER, line)
    gsub(/@@JITO_NTP@@/, JITO_NTP, line)
    gsub(/@@XDP_ENABLED@@/, XDP_ENABLED, line)
    gsub(/@@XDP_INTERFACE@@/, XDP_INTERFACE, line)
    gsub(/@@XDP_RETRANSMIT_CORES@@/, XDP_RETRANSMIT_CORES, line)
    if (line == "@@ENTRYPOINTS_BLOCK@@") { print ENTRYPOINTS_BLOCK; next }
    if (line == "@@KNOWN_VALIDATORS_BLOCK@@") { print KNOWN_VALIDATORS_BLOCK; next }
    print line
  }' "$TEMPLATE" > "$OUTPUT_FILE"

# self-check: no unfilled tokens
if grep -n '@@[A-Z_]*@@' "$OUTPUT_FILE" >/dev/null; then
  tok=$(grep -o '@@[A-Z_]*@@' "$OUTPUT_FILE" | sort -u | tr '\n' ' ')
  rm -f "$OUTPUT_FILE"
  echo "Internal error: unfilled template token(s): ${tok}— output removed." >&2
  exit 1
fi

# best-effort local YAML parse (full validation happens in CI)
if command -v python3 >/dev/null 2>&1; then
  python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$OUTPUT_FILE" 2>/dev/null \
    || { rm -f "$OUTPUT_FILE"; echo "Internal error: generated file is not valid YAML — output removed." >&2; exit 1; }
fi

echo
echo "Generated: playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml"
OUTPUT_FILE=""  # generation succeeded; cleanup must not remove it

# ---------------------------------------------------------------- optional vault step
if [ -f "$VAULT_FILE" ]; then
  : # vault exists — nothing to do
elif ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ansible-vault not found — set up secrets manually:"
  echo "  cp vault/secrets.example.yaml vault/secrets.yaml && \$EDITOR vault/secrets.yaml && ansible-vault encrypt vault/secrets.yaml"
elif prompt_yn "No vault/secrets.yaml found. Create it now (values prompted hidden, encrypted immediately)?" "y"; then
  # key list is parsed from the example so the secret contract stays single-sourced
  mapfile -t SECRET_KEYS < <(grep -E '^[a-z_]+:' "$EXAMPLE_VAULT" | cut -d: -f1)
  VAULT_PLAINTEXT_PENDING=1
  : > "$VAULT_FILE"
  chmod 600 "$VAULT_FILE"
  echo "---" >> "$VAULT_FILE"
  for key in "${SECRET_KEYS[@]}"; do
    while :; do
      read -u 3 -rsp "  ${key}: " val; echo
      [ -n "$val" ] && break
      echo "  (must not be empty)"
    done
    printf '%s: "%s"\n' "$key" "${val//\"/\\\"}" >> "$VAULT_FILE"
  done
  ansible-vault encrypt "$VAULT_FILE"
  VAULT_PLAINTEXT_PENDING=0
  echo "Encrypted vault/secrets.yaml created."
else
  echo "Skipped. Manual setup:"
  echo "  cp vault/secrets.example.yaml vault/secrets.yaml && \$EDITOR vault/secrets.yaml && ansible-vault encrypt vault/secrets.yaml"
fi

echo
echo "Next steps:"
echo "  1. Review playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml (cluster presets last verified 2026-07)."
echo "  2. Run: ansible-playbook playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml -i inventory -e host=local --connection=local --ask-vault-pass"
