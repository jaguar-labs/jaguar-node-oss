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
preset_testnet_metrics_user="testnet_write"
preset_testnet_metrics_password="c4fa841aa918bf8274e3e2a44d77568d9861b3ea"
preset_testnet_entrypoints="entrypoint.testnet.solana.com:8001 entrypoint2.testnet.solana.com:8001 entrypoint3.testnet.solana.com:8001"
preset_testnet_known_validators="5D1fNXzvv5NjV1ysLjirC4WY92RNsVH18vjmcszZd8on dDzy5SR3AXdYWVqbDEkVFdvSPCtS9ihF5kJkHCtXoFs Ft5fbkqNa76vnsjYNwjDZUXoTWpP7VYm3mtsaQckQADN eoKpUABi59aT4rR9HGS3LcMecfut9x7zJyodWWP43YQ 9QxCLckBiJc783jnMvXZubK4wH86Eqqvashtrwvcsgkv"
preset_testnet_jito_tip_payment="GJHtFqM9agxPmkeKjHny6qiRKrXZALvvFGiKf11QE7hy"
preset_testnet_jito_tip_distribution="DzvGET57TAgEDxvm3ERUM4GNcsAJdqjDLCne9sdfY4wf"
preset_testnet_jito_merkle_auth="7T4inmPmtNBX3MhLwJ9hFsSMnGJYYkKioVABSNTWVRuS"
preset_testnet_jito_shred_receiver="64.130.35.224:1002"
preset_testnet_jito_regions="ny dallas"
preset_testnet_jito_ntp="ntp.dallas.jito.wtf"
preset_testnet_port_range="8000-10000"
preset_testnet_solana_version="4.1.0-beta.3"

preset_mainnet_genesis="5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
preset_mainnet_remote_rpc="https://api.mainnet-beta.solana.com"
preset_mainnet_metrics_db="mainnet-beta"
preset_mainnet_metrics_user="mainnet-beta_write"
preset_mainnet_metrics_password="password"
preset_mainnet_entrypoints="entrypoint.mainnet-beta.solana.com:8001 entrypoint2.mainnet-beta.solana.com:8001 entrypoint3.mainnet-beta.solana.com:8001"
preset_mainnet_known_validators="7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2 GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S"
preset_mainnet_jito_tip_payment="T1pyyaTNZsKv2WcRAB8oVnk93mLJw2XzjtVYqCsaHqt"
preset_mainnet_jito_tip_distribution="4R3gSG8BpU4t19KYj8CfnbtRpnT8gtk4dvTHxVRwc2r7"
preset_mainnet_jito_merkle_auth="GZctHpWXmsZC1YHACTGGcHhYxjdRqQvTpYkb9LMvxDib"
preset_mainnet_jito_shred_receiver="141.98.216.96:1002"
preset_mainnet_jito_regions="ny amsterdam dublin frankfurt london slc singapore tokyo"
preset_mainnet_jito_ntp="ntp.dallas.jito.wtf"
preset_mainnet_port_range="8000-10000"
preset_mainnet_solana_version="4.1.0-beta.3"

# Alpenglow test cluster — VOLATILE test-cluster values, last verified: 2026-08
# (entrypoints, shred version and bank hash change on cluster restarts).
preset_alpenglow_genesis="HtRW7y9hJZaEBgH8cvUomQQjaXY5vM8J54nqbZJz7MjW"
preset_alpenglow_remote_rpc="http://185.8.106.234:8899"
preset_alpenglow_metrics_db="alpenglow-testnet"
preset_alpenglow_metrics_user="ag"
preset_alpenglow_metrics_password='!d.tWEViQRhhP.*be9!a'
preset_alpenglow_entrypoints="64.130.37.11:8000 213.239.141.16:8001"
preset_alpenglow_known_validators=""
preset_alpenglow_port_range="9000-12500"
preset_alpenglow_solana_version="4.2.0-beta.0"
# no Jito on alpenglow — empty values keep the preset lookup total
preset_alpenglow_jito_tip_payment=""
preset_alpenglow_jito_tip_distribution=""
preset_alpenglow_jito_merkle_auth=""
preset_alpenglow_jito_shred_receiver=""
preset_alpenglow_jito_regions=""
preset_alpenglow_jito_ntp=""

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
  prompt "Cluster (testnet/mainnet/alpenglow)" "testnet"
  case "$REPLY" in testnet|mainnet|alpenglow) CLUSTER="$REPLY"; break ;; *) echo "  Invalid: must be testnet, mainnet or alpenglow" ;; esac
done

IDENTITY_DEFERRED=0
while :; do
  prompt "Validator identity pubkey (base58, or 'gen' to generate on the host)" ""
  if [ "$REPLY" = "gen" ]; then
    IDENTITY_PUBKEY=""
    IDENTITY_DEFERRED=1
    echo "  Deferred: the playbook generates funded-validator-keypair.json on the host and fills the pubkey at run time."
    break
  fi
  [[ "$REPLY" =~ $RE_PUBKEY ]] && { IDENTITY_PUBKEY="$REPLY"; break; }
  echo "  Invalid: must be base58 32-44 chars, or 'gen'"
done

VOTE_DEFERRED=0
while :; do
  prompt "Vote account pubkey (base58, or 'skip' to generate a keypair on the host)" "skip"
  if [ "$REPLY" = "skip" ] || [ -z "$REPLY" ]; then
    VOTE_PUBKEY=""
    VOTE_DEFERRED=1
    echo "  Deferred: the playbook generates vote-account-keypair.json on the host; you create the account on-chain afterwards."
    break
  fi
  [[ "$REPLY" =~ $RE_PUBKEY ]] && { VOTE_PUBKEY="$REPLY"; break; }
  echo "  Invalid: must be base58 32-44 chars, or 'skip'"
done

# ---------------------------------------------------------------- disk configuration
detect_unused_disks() { # prints "path size" per bare disk: no partitions/holders, no fs, unmounted
  if [ -n "${NEW_PLAYBOOK_FAKE_UNUSED_DISKS:-}" ]; then
    # test-only hook: space-separated "dev:size" pairs simulate detections
    local pair
    for pair in $NEW_PLAYBOOK_FAKE_UNUSED_DISKS; do printf '%s %s\n' "${pair%%:*}" "${pair#*:}"; done
    return 0
  fi
  command -v lsblk >/dev/null 2>&1 || return 0
  local dev size
  while read -r dev size; do
    [ "$(lsblk -n "$dev" 2>/dev/null | wc -l)" -eq 1 ] || continue
    [ -z "$(lsblk -dn -o FSTYPE "$dev" 2>/dev/null | tr -d '[:space:]')" ] || continue
    printf '%s %s\n' "$dev" "$size"
  done < <(lsblk -dn -p -o NAME,SIZE,TYPE 2>/dev/null | awk '$3=="disk"{print $1, $2}')
}

UNUSED_DISKS=()
UNUSED_SIZES=()
while read -r dev size; do
  [ -n "$dev" ] || continue
  UNUSED_DISKS+=("$dev")
  UNUSED_SIZES+=("$size")
done < <(detect_unused_disks)

if [ "${#UNUSED_DISKS[@]}" -gt 0 ]; then
  echo
  echo "Unused disks detected on this machine (no partitions, no filesystem, unmounted):"
  for i in "${!UNUSED_DISKS[@]}"; do
    echo "  $((i+1))) ${UNUSED_DISKS[$i]} (${UNUSED_SIZES[$i]})"
  done
  echo "  (Detection runs where the wizard runs — ignore this list when preparing a playbook for another host.)"
  echo
fi

# device prompt defaults: detected unused disks in order, else static fallbacks
DEFAULT_DEV1="${UNUSED_DISKS[0]:-/dev/nvme0n1}"
DEFAULT_DEV2="${UNUSED_DISKS[1]:-/dev/nvme1n1}"
DEFAULT_DEV3="${UNUSED_DISKS[2]:-/dev/nvme4n1}"

# role→disk map: which device carries each role; every generation path fills it
ROLES="ledger accounts snapshots"
ROLE_DISK_ledger=""
ROLE_DISK_accounts=""
ROLE_DISK_snapshots=""

mount_dir_for_disk() { # <dev> -> mount dir derived from the role set on that device
  local roles="" r v
  for r in $ROLES; do
    v="ROLE_DISK_$r"
    [ "${!v}" = "$1" ] && roles+="${roles:+_}$r"
  done
  if [ "$roles" = "ledger_accounts_snapshots" ]; then
    printf '/mnt/solana'
  else
    printf '/mnt/solana_%s' "$roles"
  fi
}

# -------- selection-first: which detected disks to use (none -> classic flow)
ASSIGNMENT_DONE=0
if [ "${#UNUSED_DISKS[@]}" -gt 0 ]; then
  while :; do
    prompt "Select disks to use (numbers or /dev paths comma-separated, 'all', or 'none' for the classic prompts)" "all"
    sel="${REPLY,,}"; sel="${sel// /}"
    [ "$sel" = "none" ] && break
    SELECTED=()
    if [ "$sel" = "all" ]; then
      SELECTED=("${UNUSED_DISKS[@]}")
    else
      ok=1
      IFS=',' read -ra stoks <<<"$sel"
      for t in "${stoks[@]}"; do
        pick=""
        if [[ "$t" =~ ^[0-9]+$ ]]; then
          idx=$((t-1))
          [ "$idx" -ge 0 ] && [ "$idx" -lt "${#UNUSED_DISKS[@]}" ] && pick="${UNUSED_DISKS[$idx]}"
        else
          for d in "${UNUSED_DISKS[@]}"; do [ "$d" = "$t" ] && pick="$d"; done
        fi
        if [ -z "$pick" ]; then echo "  Invalid selection '$t' (use the listed numbers or device paths)"; ok=0; continue; fi
        case " ${SELECTED[*]-} " in *" $pick "*) ;; *) SELECTED+=("$pick") ;; esac
      done
      [ "$ok" -eq 1 ] || continue
    fi
    if [ "${#SELECTED[@]}" -lt 1 ] || [ "${#SELECTED[@]}" -gt 3 ]; then
      echo "  Invalid: select between 1 and 3 disks (three roles: ledger, accounts, snapshots)"
      continue
    fi
    ASSIGNMENT_DONE=1
    break
  done
fi

if [ "$ASSIGNMENT_DONE" -eq 1 ]; then
  # -------- role prompts over the selected disks only
  while :; do
    ROLE_DISK_ledger=""
    ROLE_DISK_accounts=""
    ROLE_DISK_snapshots=""
    n="${#SELECTED[@]}"
    for i in "${!SELECTED[@]}"; do
      dev="${SELECTED[$i]}"
      remaining=""
      for r in $ROLES; do v="ROLE_DISK_$r"; [ -z "${!v}" ] && remaining+="${remaining:+,}$r"; done
      if [ "$i" -eq $((n-1)) ]; then
        # last selected disk: it must carry everything still unassigned
        def="$remaining"
        [ "$def" = "ledger,accounts,snapshots" ] && def="all"
      elif [ "$i" -eq 0 ]; then
        def="ledger"
      else
        def="accounts"
      fi
      while :; do
        prompt "Use ${dev} for (ledger/accounts/snapshots comma-separated, all)" "$def"
        ans="${REPLY,,}"; ans="${ans// /}"
        [ "$ans" = "all" ] && ans="ledger,accounts,snapshots"
        ok=1
        IFS=',' read -ra toks <<<"$ans"
        for t in "${toks[@]}"; do
          case "$t" in
            ledger|accounts|snapshots)
              v="ROLE_DISK_$t"
              if [ -n "${!v}" ]; then echo "  Invalid: $t is already assigned to ${!v}"; ok=0; fi ;;
            *) echo "  Invalid token '$t' (use ledger/accounts/snapshots or all)"; ok=0 ;;
          esac
        done
        [ "$ok" -eq 1 ] || continue
        if [ "$i" -eq $((n-1)) ]; then
          miss=""
          for r in ${remaining//,/ }; do
            case ",$ans," in *",$r,"*) ;; *) miss+="${miss:+ }$r" ;; esac
          done
          if [ -n "$miss" ]; then
            echo "  Invalid: role(s) $miss still need a disk and ${dev} is the last selected one — include them (Enter = $def)"
            continue
          fi
        fi
        for t in "${toks[@]}"; do printf -v "ROLE_DISK_$t" '%s' "$dev"; done
        break
      done
    done
    missing=""
    for r in $ROLES; do v="ROLE_DISK_$r"; [ -z "${!v}" ] && missing+=" $r"; done
    [ -z "$missing" ] && break
    echo "  Unassigned role(s):$missing — assign every role across the selected disks; restarting role prompts."
  done
else
  # -------- classic layout flow
  while :; do
    prompt "Disk layout: separate NVMe per ledger/accounts/snapshots, or all on one disk (separate/single)" "separate"
    case "$REPLY" in separate|single) DISK_SHAPE="$REPLY"; break ;; *) echo "  Invalid: must be separate or single" ;; esac
  done
  if [ "$DISK_SHAPE" = "separate" ]; then
    prompt_valid "Ledger disk device" "$DEFAULT_DEV1" "$RE_DEV" "must look like /dev/..."
    ROLE_DISK_ledger="$REPLY"
    prompt_valid "Accounts disk device" "$DEFAULT_DEV2" "$RE_DEV" "must look like /dev/..."
    ROLE_DISK_accounts="$REPLY"
    prompt_valid "Snapshots disk device" "$DEFAULT_DEV3" "$RE_DEV" "must look like /dev/..."
    ROLE_DISK_snapshots="$REPLY"
  else
    prompt_valid "Disk device (holds ledger, accounts and snapshots)" "$DEFAULT_DEV1" "$RE_DEV" "must look like /dev/..."
    ROLE_DISK_ledger="$REPLY"
    ROLE_DISK_accounts="$REPLY"
    ROLE_DISK_snapshots="$REPLY"
    if [ "$CLUSTER" = "mainnet" ]; then
      echo "  NOTE: separate NVMe devices for ledger/accounts/snapshots are recommended on mainnet."
    fi
  fi
fi

LEDGER_PATH="$(mount_dir_for_disk "$ROLE_DISK_ledger")/ledger"
ACCOUNTS_PATH="$(mount_dir_for_disk "$ROLE_DISK_accounts")/accounts"
SNAPSHOTS_PATH="$(mount_dir_for_disk "$ROLE_DISK_snapshots")/snapshots"

prompt_valid "Validator log path" "/mnt/solana/log" "$RE_ABSPATH" "must be an absolute path"
LOG_PATH="$REPLY"

# cluster presets (indirect expansion off the chosen cluster)
p() { local v="preset_${CLUSTER}_$1"; printf '%s' "${!v}"; }

JITO_ENABLED="False"
JITO_COMMISSION_BPS="0"
JITO_BLOCK_ENGINE_URL=""
if [ "$CLUSTER" = "alpenglow" ]; then
  echo "Jito is not available on the alpenglow cluster — disabled."
elif prompt_yn "Enable Jito MEV?" "y"; then
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
fi

ALPENGLOW_ENABLED="False"
ALPENGLOW_SHRED_VERSION=""
ALPENGLOW_BANK_HASH=""
if [ "$CLUSTER" = "alpenglow" ]; then
  ALPENGLOW_ENABLED="True"
  echo "NOTE: shred version and bank hash change when the alpenglow cluster restarts — check the latest values."
  prompt_valid "Expected shred version" "10638" '^[0-9]+$' "must be numeric"
  ALPENGLOW_SHRED_VERSION="$REPLY"
  prompt_valid "Expected bank hash" "EXrkvP5Y6GG1qdbqU8LVPZqtNYNuWKEZFVARxF9TQh8H" "$RE_PUBKEY" "must be a base58 hash"
  ALPENGLOW_BANK_HASH="$REPLY"
fi

if prompt_yn "Enable XDP retransmit?" "n"; then
  XDP_ENABLED="true"
  # bond awareness: XDP and ring tuning need a physical NIC, never the bond master
  XDP_DEFAULT_IFACE=""
  if [ -r /sys/class/net/bonding_masters ]; then
    read -ra XDP_BONDS < /sys/class/net/bonding_masters
    for bond in "${XDP_BONDS[@]}"; do
      members="$(cat "/sys/class/net/$bond/bonding/slaves" 2>/dev/null || true)"
      active="$(cat "/sys/class/net/$bond/bonding/active_slave" 2>/dev/null || true)"
      echo "  Bond detected: $bond (members: ${members:-none}${active:+; active: $active})"
      if [ -z "$XDP_DEFAULT_IFACE" ]; then
        if [ -n "$active" ]; then XDP_DEFAULT_IFACE="$active"; else XDP_DEFAULT_IFACE="${members%% *}"; fi
      fi
    done
    if [ -n "$XDP_DEFAULT_IFACE" ]; then
      echo "  XDP must use a physical member, not the bond — proposing $XDP_DEFAULT_IFACE"
    fi
  fi
  while :; do
    prompt_valid "XDP NIC interface (bond MEMBER if bonded)" "$XDP_DEFAULT_IFACE" "$RE_IFACE" "interface name"
    if [ -e "/sys/class/net/$REPLY/bonding" ]; then
      echo "  Invalid: $REPLY is a bond master; use one of its members: $(cat "/sys/class/net/$REPLY/bonding/slaves" 2>/dev/null)"
      continue
    fi
    break
  done
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

yaml_list_block() { # yaml_list_block <space separated items> -> 6-space indented "- item" lines ([] when empty)
  local out="" item
  for item in $1; do out+="      - ${item}"$'\n'; done
  if [ -z "$out" ]; then printf '      []'; return; fi
  printf '%s' "${out%$'\n'}"
}

DISK_FS_OPTIONS="rw,noatime,nodiratime,discard,attr2,inode64,logbufs=8,logbsize=256k,allocsize=64k"

# shellcheck disable=SC2016  # $UUID etc. are runtime expressions of the GENERATED script
disk_setup_cmds() { # disk_setup_cmds <dev> <mount_dir> -> commands for one manually prepared disk
  printf '  mkfs.xfs %s\n' "$1"
  printf '  mkdir -p %s\n' "$2"
  printf '  mount -o %s %s %s\n' "$DISK_FS_OPTIONS" "$1" "$2"
  printf '  UUID=$(blkid -s UUID -o value %s)\n' "$1"
  printf '  grep -q " %s " /etc/fstab || echo "UUID=$UUID %s xfs %s 0 0" >> /etc/fstab\n' "$2" "$2" "$DISK_FS_OPTIONS"
}

unique_role_disks() { # devices from the map, role order, deduplicated
  local seen="" r v
  for r in $ROLES; do
    v="ROLE_DISK_$r"
    case " $seen " in *" ${!v} "*) continue ;; esac
    seen+="${seen:+ }${!v}"
    printf '%s\n' "${!v}"
  done
}

ENTRYPOINTS_BLOCK="$(yaml_list_block "$(p entrypoints)")"
KNOWN_VALIDATORS_BLOCK="$(yaml_list_block "$(p known_validators)")"

awk \
  -v VALIDATOR_NAME="$VALIDATOR_NAME" \
  -v CLUSTER="$CLUSTER" \
  -v IDENTITY_PUBKEY="$IDENTITY_PUBKEY" \
  -v VOTE_PUBKEY="$VOTE_PUBKEY" \
  -v LEDGER_PATH="$LEDGER_PATH" \
  -v ACCOUNTS_PATH="$ACCOUNTS_PATH" \
  -v SNAPSHOTS_PATH="$SNAPSHOTS_PATH" \
  -v LOG_PATH="$LOG_PATH" \
  -v GENESIS_HASH="$(p genesis)" \
  -v SOLANA_VERSION="$(p solana_version)" \
  -v DYNAMIC_PORT_RANGE="$(p port_range)" \
  -v ALPENGLOW_ENABLED="$ALPENGLOW_ENABLED" \
  -v ALPENGLOW_SHRED_VERSION="$ALPENGLOW_SHRED_VERSION" \
  -v ALPENGLOW_BANK_HASH="$ALPENGLOW_BANK_HASH" \
  -v REMOTE_RPC="$(p remote_rpc)" \
  -v METRICS_DB="$(p metrics_db)" \
  -v METRICS_USER="$(p metrics_user)" \
  -v METRICS_PASSWORD="$(p metrics_password)" \
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
    gsub(/@@LEDGER_PATH@@/, LEDGER_PATH, line)
    gsub(/@@ACCOUNTS_PATH@@/, ACCOUNTS_PATH, line)
    gsub(/@@SNAPSHOTS_PATH@@/, SNAPSHOTS_PATH, line)
    gsub(/@@LOG_PATH@@/, LOG_PATH, line)
    gsub(/@@GENESIS_HASH@@/, GENESIS_HASH, line)
    gsub(/@@SOLANA_VERSION@@/, SOLANA_VERSION, line)
    gsub(/@@DYNAMIC_PORT_RANGE@@/, DYNAMIC_PORT_RANGE, line)
    gsub(/@@ALPENGLOW_ENABLED@@/, ALPENGLOW_ENABLED, line)
    gsub(/@@ALPENGLOW_SHRED_VERSION@@/, ALPENGLOW_SHRED_VERSION, line)
    gsub(/@@ALPENGLOW_BANK_HASH@@/, ALPENGLOW_BANK_HASH, line)
    gsub(/@@REMOTE_RPC@@/, REMOTE_RPC, line)
    gsub(/@@METRICS_DB@@/, METRICS_DB, line)
    gsub(/@@METRICS_USER@@/, METRICS_USER, line)
    gsub(/@@METRICS_PASSWORD@@/, METRICS_PASSWORD, line)
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

# ------------------------------------------------------- disk setup script (always)
# Ansible never touches block devices; this script is the only format/mount path.
{
  SETUP_SCRIPT_NAME="disk-setup-${VALIDATOR_NAME}.sh"
  SETUP_SCRIPT="$REPO_ROOT/playbooks/$SETUP_SCRIPT_NAME"
  # shellcheck disable=SC2016  # ${1-} belongs to the generated script's runtime
  {
    printf '#!/usr/bin/env bash\n'
    printf '# Disk preparation for playbooks/%s-%s-profile.yaml — generated by bin/new-playbook.sh.\n' "$VALIDATOR_NAME" "$CLUSTER"
    printf '# Run on the TARGET HOST as root. DESTRUCTIVE: contains mkfs (no -f, so an\n'
    printf '# already-formatted disk fails loudly instead of being wiped).\n'
    printf 'set -euo pipefail\n\n'
    printf 'run() {\n'
    printf '  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT\n'
    while IFS= read -r dev; do
      disk_setup_cmds "$dev" "$(mount_dir_for_disk "$dev")"
    done < <(unique_role_disks)
    printf '  mount -a\n'
    while IFS= read -r dev; do
      printf '  findmnt %s\n' "$(mount_dir_for_disk "$dev")"
    done < <(unique_role_disks)
    printf '}\n\n'
    printf 'if [ "${1-}" != "--yes" ]; then\n'
    printf '  echo "DRY RUN — commands that would execute:"\n'
    printf "  declare -f run | sed '1,2d;\$d'\n"
    printf '  echo\n'
    printf '  echo "Re-run with --yes to execute (DESTRUCTIVE: mkfs)."\n'
    printf '  exit 1\n'
    printf 'fi\n'
    printf 'run\n'
  } > "$SETUP_SCRIPT"
  chmod +x "$SETUP_SCRIPT"
  echo
  echo "Disk preparation: run these commands on the target host as root BEFORE the playbook"
  echo "(skip if the disks are already formatted and mounted)."
  echo "Saved to playbooks/$SETUP_SCRIPT_NAME (gitignored; regenerate by re-running the wizard):"
  bash "$SETUP_SCRIPT" 2>/dev/null | sed '1d' || true
}

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
echo "  2. Prepare the disks FIRST (unless already formatted+mounted): run playbooks/disk-setup-${VALIDATOR_NAME}.sh"
echo "     on the target host as root, with --yes to execute."
echo "  3. Run: ansible-playbook playbooks/${VALIDATOR_NAME}-${CLUSTER}-profile.yaml -i inventory -e host=local --connection=local --ask-vault-pass"
if [ "$IDENTITY_DEFERRED" -eq 1 ]; then
  echo "  4. Identity deferred: the playbook generates /home/solana/.secrets/funded-validator-keypair.json"
  echo "     on the host and fills validator_identity_pubkey automatically during the run."
fi
if [ "$VOTE_DEFERRED" -eq 1 ]; then
  echo "  5. Vote account deferred: after provisioning, create it ON-CHAIN (needs a funded identity):"
  echo "       solana create-vote-account /home/solana/.secrets/vote-account-keypair.json \\"
  echo "         /home/solana/.secrets/funded-validator-keypair.json <WITHDRAWER_ADDRESS>"
  echo "     Until then the validator cannot vote and watchtower will alert — that is expected."
fi
if [ "$CLUSTER" = "alpenglow" ]; then
  echo "  6. Alpenglow: after provisioning, build the validator with ~/build-alpenglow.sh"
  echo "     (default ref v4.2.0-beta.0), then ~/build-solana-cli.sh for the CLI tools."
  echo "     Presets (entrypoints, shred version, bank hash) are volatile test-cluster"
  echo "     values (last verified 2026-08) — re-check them after cluster restarts."
fi
