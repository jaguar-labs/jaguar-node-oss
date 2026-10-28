#!/usr/bin/env bash
# node-transition.sh: hand the voting identity over between two validator hosts,
# Agave or Firedancer on either side, in either direction.
#
# Source of truth: jaguar-node-oss, roles/validator/files/node-transition.sh.
# The same file is installed unchanged on Firedancer hosts (firedancer-support).
# Nothing host-specific lives here: everything comes from
# /etc/node-transition.d/<name>.conf, rendered by Ansible from the profile.
#
# Usage:
#   node-transition.sh [<name>] [--check | --arm | --take-over] [--dry-run] [--now] [--yes]
#
#   (no mode)     Run on the ACTIVE host: pre-flight, wait for a safe window,
#                 give the identity up here, carry the consensus state file
#                 (vote history under Alpenglow, tower otherwise) to the peer,
#                 take the identity there. One command, same steps on every
#                 client mix.
#   --check       Pre-flight only, nothing changes. Prints both link targets,
#                 both running identities, both armed vote accounts, both
#                 client versions.
#   --arm         Run on a STANDBY whose client takes the vote account from a
#                 start script (Agave): point start-node.sh at the named
#                 validator's script, restart, wait for catch-up.
#   --take-over   Run on a STANDBY when the active host is unreachable: take
#                 the identity WITHOUT a state file, after the gate (armed,
#                 caught up, no local state file, operator confirmation).
#   --dry-run     Print every command instead of running it. Pre-flight
#                 failures are reported, not fatal.
#   --now         Skip the wait for a safe window.
#   --yes         Skip the take-over confirmation prompt.
#
# <name> may be omitted when exactly one configuration exists.
set -euo pipefail

CONF_DIR="${NODE_TRANSITION_CONF_DIR:-/etc/node-transition.d}"
CATCHUP_SLOTS="${NODE_TRANSITION_CATCHUP_SLOTS:-150}"   # cluster slot - local slot, max
FD_ROOT_DISTANCE_MAX="${NODE_TRANSITION_FD_ROOT_DISTANCE:-64}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

MODE=transition DRY=0 NOW=0 YES=0 NAME=""
usage() { sed -n '2,33p' "$0"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE=check ;;
    --arm)       MODE=arm ;;
    --take-over) MODE=takeover ;;
    --dry-run)   DRY=1 ;;
    --now)       NOW=1 ;;
    --yes)       YES=1 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)           [ -z "$NAME" ] || { echo "only one <name> is accepted" >&2; exit 2; }; NAME="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- helpers
log()  { printf '[transition] %s\n' "$*"; }
warn() { printf '[transition] WARNING: %s\n' "$*" >&2; }
die()  { printf '[transition] ERROR: %s\n' "$*" >&2; exit 1; }
# run: state-changing local command; printed instead of executed under --dry-run.
run() { if [ "$DRY" = 1 ]; then printf '[dry-run] %s\n' "$*"; else log "+ $*"; "$@"; fi; }
# as_user: run a local command as $LOCAL_USER (no-op when we already are).
as_user() {
  if [ "$(id -un)" = "$LOCAL_USER" ]; then "$@"
  elif [ "$(id -u)" = 0 ]; then sudo -u "$LOCAL_USER" -H "$@"
  else die "run this as $LOCAL_USER or root (current: $(id -un))"; fi
}
remote()     { ssh "${SSH_OPTS[@]}" "$PEER_USER@$PEER_HOST" "$1"; }
remote_run() { if [ "$DRY" = 1 ]; then printf '[dry-run] ssh %s@%s %q\n' "$PEER_USER" "$PEER_HOST" "$1"; else log "+ ssh $PEER_USER@$PEER_HOST $1"; remote "$1"; fi; }
peer_sudo()  { if [ "$PEER_SUDO" = yes ]; then printf 'sudo -n %s' "$1"; else printf '%s' "$1"; fi; }
rpc() { # rpc <url> <method> [params-json]
  curl -sf -m 8 "$1" -X POST -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":${3:-[]}}"
}
json_get() { python3 -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d=d[int(k)] if k.lstrip("-").isdigit() else d[k]
print(d)' "$1" 2>/dev/null; }

# ---------------------------------------------------------------- configuration
load_conf() {
  [ -d "$CONF_DIR" ] || die "no configuration directory $CONF_DIR (declare transition_peers in the host profile)"
  if [ -z "$NAME" ]; then
    mapfile -t confs < <(find "$CONF_DIR" -maxdepth 1 -name '*.conf' -printf '%f\n' | sed 's/\.conf$//' | sort)
    case "${#confs[@]}" in
      0) die "no configuration in $CONF_DIR (declare transition_peers in the host profile)" ;;
      1) NAME="${confs[0]}" ;;
      *) die "several configurations: ${confs[*]} — give the <name>" ;;
    esac
  fi
  CONF="$CONF_DIR/$NAME.conf"
  [ -r "$CONF" ] || die "no configuration $CONF"
  # shellcheck disable=SC1090
  . "$CONF"
  local k; for k in NAME LOCAL_CLIENT LOCAL_USER LOCAL_SERVICE LOCAL_STATE_DIR LOCAL_FUNDED_KEYPAIR \
      LOCAL_UNFUNDED_KEYPAIR LOCAL_IDENTITY_LINK LOCAL_VOTE_ACCOUNT LOCAL_ADMIN LOCAL_RPC_PORT; do
    [ -n "${!k:-}" ] || die "$CONF: $k is empty"
  done
  case "$LOCAL_CLIENT" in agave|firedancer) ;; *) die "$CONF: LOCAL_CLIENT must be agave or firedancer" ;; esac
  if [ "$LOCAL_CLIENT" = firedancer ]; then
    [ -n "${LOCAL_IDENTITY_SCRIPT:-}" ] && [ -n "${LOCAL_CONFIG:-}" ] || die "$CONF: firedancer needs LOCAL_IDENTITY_SCRIPT and LOCAL_CONFIG"
    export FIREDANCER_CONFIG_TOML="$LOCAL_CONFIG"
  fi
  if [ "$MODE" = transition ] || [ "$MODE" = check ]; then
    for k in PEER_HOST PEER_USER PEER_CLIENT PEER_STATE_DIR PEER_FUNDED_KEYPAIR PEER_UNFUNDED_KEYPAIR \
        PEER_IDENTITY_LINK PEER_ADMIN PEER_VOTE_ACCOUNT PEER_RPC_PORT; do
      [ -n "${!k:-}" ] || die "$CONF: $k is empty"
    done
    case "$PEER_CLIENT" in agave|firedancer) ;; *) die "$CONF: PEER_CLIENT must be agave or firedancer" ;; esac
    [ "$PEER_CLIENT" != firedancer ] || [ -n "${PEER_IDENTITY_SCRIPT:-}" ] || die "$CONF: firedancer peer needs PEER_IDENTITY_SCRIPT"
  fi
  PEER_SUDO="${PEER_SUDO:-no}"; CLUSTER_RPC_URL="${CLUSTER_RPC_URL:-}"
  PEER_CLI_BIN="${PEER_CLI_BIN:-}"; PEER_CONFIG="${PEER_CONFIG:-}"; PEER_METRICS_PORT="${PEER_METRICS_PORT:-}"
  LOCAL_CLI_BIN="${LOCAL_CLI_BIN:-}"; LOCAL_METRICS_PORT="${LOCAL_METRICS_PORT:-}"
  LOCAL_START_SCRIPT="${LOCAL_START_SCRIPT:-}"; LOCAL_START_LINK="${LOCAL_START_LINK:-}"
}

# ---------------------------------------------------------------- client operations
# Each takes "local" or "peer" and uses that side's variables.
side_var() { local side="$1" key="$2"; if [ "$side" = local ]; then printf '%s' "${!key}"; else local p="PEER_${key#LOCAL_}"; printf '%s' "${!p:-}"; fi; }
on_side() { local side="$1"; shift; if [ "$side" = local ]; then bash -c "$1"; else remote "$1"; fi; }

pubkey_cmd() { # pubkey_cmd <side> <keypair>  -> shell command printing the pubkey
  local side="$1" file="$2" client admin cli cfg
  client="$(side_var "$side" LOCAL_CLIENT)"; admin="$(side_var "$side" LOCAL_ADMIN)"
  cli="$(side_var "$side" LOCAL_CLI_BIN)"; cfg="$(side_var "$side" LOCAL_CONFIG)"
  if [ "$client" = firedancer ]; then printf 'FIREDANCER_CONFIG_TOML=%q %q keys pubkey %q' "$cfg" "$admin" "$file"
  else printf '%q/solana-keygen pubkey %q' "$cli" "$file"; fi
}
pubkey_of()    { on_side "$1" "$(pubkey_cmd "$1" "$2")" | tail -n1; }
sha1_of()      { on_side "$1" "sha1sum < $(printf '%q' "$2") | cut -d' ' -f1"; }
link_target()  { on_side "$1" "readlink -f $(printf '%q' "$2") 2>/dev/null || true"; }
running_identity() { # from the node's own RPC
  local port; port="$(side_var "$1" LOCAL_RPC_PORT)"
  on_side "$1" "curl -sf -m 8 http://127.0.0.1:$port -X POST -H content-type:application/json -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getIdentity\"}'" | json_get result.identity
}
armed_vote_account() { # the vote account the running process was started for
  local side="$1" client svc cfg
  client="$(side_var "$side" LOCAL_CLIENT)"; svc="$(side_var "$side" LOCAL_SERVICE)"; cfg="$(side_var "$side" LOCAL_CONFIG)"
  if [ "$client" = firedancer ]; then
    on_side "$side" "sed -n 's/^[[:space:]]*vote_account[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' $(printf '%q' "$cfg") | head -n1"
  else
    on_side "$side" "pid=\$(systemctl show -p MainPID --value $(printf '%q' "${svc:-solana-validator}") 2>/dev/null); [ -n \"\$pid\" ] && [ \"\$pid\" != 0 ] && tr '\\0' '\\n' < /proc/\$pid/cmdline | grep -A1 -x -- --vote-account | tail -n1"
  fi
}
client_version() {
  local side="$1" admin cfg; admin="$(side_var "$side" LOCAL_ADMIN)"; cfg="$(side_var "$side" LOCAL_CONFIG)"
  on_side "$side" "FIREDANCER_CONFIG_TOML=$(printf '%q' "$cfg") $(printf '%q' "$admin") --version 2>/dev/null | head -n1"
}
state_file() { # state_file <side> <pubkey> -> file name present in that side's state dir, or ""
  local side="$1" pk="$2" dir; dir="$(side_var "$side" LOCAL_STATE_DIR)"
  on_side "$side" "for f in vote_history-$pk.bin tower-1_9-$pk.bin; do [ -s $(printf '%q' "$dir")/\$f ] && { echo \$f; break; }; done; true"
}
caught_up() { # caught_up <side> -> prints a status line, returns 0 when caught up
  local side="$1" client port mport local_slot cluster_slot dist
  client="$(side_var "$side" LOCAL_CLIENT)"; port="$(side_var "$side" LOCAL_RPC_PORT)"; mport="$(side_var "$side" LOCAL_METRICS_PORT)"
  if [ "$client" = firedancer ] && [ -n "$mport" ]; then
    dist="$(on_side "$side" "curl -sf -m 5 http://127.0.0.1:$mport/metrics | sed -n 's/^replay_root_slot_distance{[^}]*} //p' | head -n1")"
    [ -n "$dist" ] || { echo "metrics unavailable on port $mport"; return 1; }
    printf 'root distance %s (max %s)' "$dist" "$FD_ROOT_DISTANCE_MAX"; [ "$dist" -le "$FD_ROOT_DISTANCE_MAX" ] || { echo; return 1; }
    [ -n "$CLUSTER_RPC_URL" ] && printf '; ' || echo
  fi
  if [ -n "$CLUSTER_RPC_URL" ]; then
    local_slot="$(on_side "$side" "curl -sf -m 8 http://127.0.0.1:$port -X POST -H content-type:application/json -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSlot\",\"params\":[{\"commitment\":\"processed\"}]}'" | json_get result)"
    cluster_slot="$(rpc "$CLUSTER_RPC_URL" getSlot '[{"commitment":"processed"}]' | json_get result)"
    [ -n "$local_slot" ] && [ -n "$cluster_slot" ] || { echo "slot comparison failed (local=$local_slot cluster=$cluster_slot)"; return 1; }
    echo "local slot $local_slot, cluster slot $cluster_slot (max gap $CATCHUP_SLOTS)"
    [ $((cluster_slot - local_slot)) -le "$CATCHUP_SLOTS" ] || return 1
  elif [ "$client" = agave ]; then
    local cli; cli="$(side_var "$side" LOCAL_CLI_BIN)"
    on_side "$side" "timeout 60 $(printf '%q' "$cli")/solana catchup --our-localhost $port 2>&1 | tail -n1" || { echo "solana catchup did not report caught up within 60s"; return 1; }
  fi
  return 0
}
wait_window() {
  [ "$NOW" = 1 ] && { log "--now: skipping the wait for a safe window"; return; }
  if [ "$LOCAL_CLIENT" = firedancer ]; then
    run "$(fd_live_bin)" wait --config "$LOCAL_CONFIG"
  else
    run as_user "$LOCAL_ADMIN" -l "$LOCAL_STATE_DIR" wait-for-restart-window --min-idle-time 2 --skip-new-snapshot-check
  fi
}
fd_live_bin() { # admin commands must come from the running validator's binary
  local pid bin; pid="$(systemctl show -p MainPID --value "$LOCAL_SERVICE" 2>/dev/null || echo 0)"
  bin="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
  if [ -x "$bin" ] && [ "$(basename "$bin")" = firedancer ]; then printf '%s' "$bin"; else printf '%s' "$LOCAL_ADMIN"; fi
}
local_give_up() {
  if [ "$LOCAL_CLIENT" = firedancer ]; then
    run "$LOCAL_IDENTITY_SCRIPT" unstaked                      # also moves identity.json
  else
    run as_user "$LOCAL_ADMIN" -l "$LOCAL_STATE_DIR" set-identity "$LOCAL_UNFUNDED_KEYPAIR"
    run as_user ln -sfn "$LOCAL_UNFUNDED_KEYPAIR" "$LOCAL_IDENTITY_LINK"
  fi
}
local_take() { # local_take [state-file-name]  (no file = emergency)
  local file="${1:-}" flag=""
  if [ "$LOCAL_CLIENT" = firedancer ]; then
    if [ -n "$file" ]; then run "$LOCAL_IDENTITY_SCRIPT" staked --vote-history-file "$LOCAL_STATE_DIR/$file"
    else run "$LOCAL_IDENTITY_SCRIPT" staked --do-not-require-vote-history --yes; fi
  else
    if [ -z "$file" ]; then
      if "$LOCAL_ADMIN" set-identity --help 2>/dev/null | grep -q -- --do-not-require-vote-history; then flag=--do-not-require-vote-history; fi
    elif [[ "$file" == tower-* ]]; then flag=--require-tower; fi
    # shellcheck disable=SC2086
    run as_user "$LOCAL_ADMIN" -l "$LOCAL_STATE_DIR" set-identity $flag "$LOCAL_FUNDED_KEYPAIR"
    run as_user ln -sfn "$LOCAL_FUNDED_KEYPAIR" "$LOCAL_IDENTITY_LINK"
  fi
}
peer_take() { # peer_take <state-file-name>
  local file="$1" flag=""
  if [ "$PEER_CLIENT" = firedancer ]; then
    remote_run "$(peer_sudo "$PEER_IDENTITY_SCRIPT staked --vote-history-file $PEER_STATE_DIR/$file")"
  else
    [[ "$file" == tower-* ]] && flag=" --require-tower"
    remote_run "$PEER_ADMIN -l $PEER_STATE_DIR set-identity$flag $PEER_FUNDED_KEYPAIR"
    remote_run "ln -sfn $PEER_FUNDED_KEYPAIR $PEER_IDENTITY_LINK"
  fi
}

# ---------------------------------------------------------------- pre-flight
FAILS=0
chk() { # chk <label> <ok:0|1> [detail]
  if [ "$2" = 0 ]; then printf '  [ok]   %s%s\n' "$1" "${3:+ — $3}"
  else printf '  [FAIL] %s%s\n' "$1" "${3:+ — $3}"; FAILS=$((FAILS+1)); fi
}
preflight() {
  local funded_pk local_unf_pk peer_unf_pk l_sha p_sha l_link p_link l_id p_id p_vote p_state l_ver p_ver cu
  log "pre-flight for '$NAME': $LOCAL_CLIENT (this host) -> $PEER_CLIENT ($PEER_USER@$PEER_HOST)"
  if remote 'exit 0' 2>/dev/null; then chk "ssh $PEER_USER@$PEER_HOST (batch mode)" 0; else chk "ssh $PEER_USER@$PEER_HOST (batch mode)" 1; log "peer unreachable: remaining peer checks skipped"; return; fi
  funded_pk="$(pubkey_of local "$LOCAL_FUNDED_KEYPAIR" || true)"
  [ -n "$funded_pk" ] || die "cannot read the pubkey of $LOCAL_FUNDED_KEYPAIR"
  l_sha="$(sha1_of local "$LOCAL_FUNDED_KEYPAIR")"; p_sha="$(sha1_of peer "$PEER_FUNDED_KEYPAIR" || true)"
  chk "funded key identical on both hosts ($funded_pk)" "$([ -n "$p_sha" ] && [ "$l_sha" = "$p_sha" ] && echo 0 || echo 1)"
  l_sha="$(sha1_of local "$LOCAL_UNFUNDED_KEYPAIR")"; p_sha="$(sha1_of peer "$PEER_UNFUNDED_KEYPAIR" || true)"
  chk "unfunded keys differ" "$([ -n "$p_sha" ] && [ "$l_sha" != "$p_sha" ] && echo 0 || echo 1)"
  local_unf_pk="$(pubkey_of local "$LOCAL_UNFUNDED_KEYPAIR" || true)"; peer_unf_pk="$(pubkey_of peer "$PEER_UNFUNDED_KEYPAIR" || true)"
  l_link="$(link_target local "$LOCAL_IDENTITY_LINK")"; p_link="$(link_target peer "$PEER_IDENTITY_LINK")"
  l_id="$(running_identity local || true)"; p_id="$(running_identity peer || true)"
  chk "this host: link -> funded" "$([ "$l_link" = "$(readlink -f "$LOCAL_FUNDED_KEYPAIR")" ] && echo 0 || echo 1)" "$l_link"
  chk "this host: running identity is funded" "$([ "$l_id" = "$funded_pk" ] && echo 0 || echo 1)" "${l_id:-no RPC answer}"
  chk "peer: link -> unfunded" "$([ -n "$p_link" ] && [ "$p_link" = "$(remote "readlink -f $(printf '%q' "$PEER_UNFUNDED_KEYPAIR")" || true)" ] && echo 0 || echo 1)" "$p_link"
  chk "peer: running identity is its unfunded key" "$([ -n "$p_id" ] && [ "$p_id" = "$peer_unf_pk" ] && echo 0 || echo 1)" "${p_id:-no RPC answer}"
  p_vote="$(armed_vote_account peer || true)"
  if [ "$p_vote" = "$PEER_VOTE_ACCOUNT" ]; then chk "peer armed for vote account $PEER_VOTE_ACCOUNT" 0
  else chk "peer armed for vote account $PEER_VOTE_ACCOUNT" 1 "runs ${p_vote:-unknown}; fix on the peer with: node-transition.sh $NAME --arm"; fi
  STATE_FILE="$(state_file local "$funded_pk")"
  chk "state file for $funded_pk in $LOCAL_STATE_DIR" "$([ -n "$STATE_FILE" ] && echo 0 || echo 1)" "${STATE_FILE:-neither vote_history-<pk>.bin nor tower-1_9-<pk>.bin}"
  p_state="$(remote "[ -d $(printf '%q' "$PEER_STATE_DIR") ] && [ -w $(printf '%q' "$PEER_STATE_DIR") ] && echo ok" || true)"
  chk "peer state dir $PEER_STATE_DIR writable by $PEER_USER" "$([ "$p_state" = ok ] && echo 0 || echo 1)"
  cu="$(caught_up peer)" && chk "peer caught up" 0 "$cu" || chk "peer caught up" 1 "$cu"
  if [ "$PEER_CLIENT" = firedancer ] && [ "$PEER_SUDO" = yes ]; then
    chk "peer: sudo -n $PEER_IDENTITY_SCRIPT allowed" "$(remote "sudo -n -l $(printf '%q' "$PEER_IDENTITY_SCRIPT") >/dev/null 2>&1" && echo 0 || echo 1)"
  fi
  l_ver="$(client_version local || true)"; p_ver="$(client_version peer || true)"
  log "versions: this host $LOCAL_CLIENT ${l_ver:-?} | peer $PEER_CLIENT ${p_ver:-?}"
  log "armed vote accounts: this host $(armed_vote_account local || echo '?') | peer ${p_vote:-?}"
}
gate() { # abort on pre-flight failures unless dry-run
  [ "$FAILS" = 0 ] && return
  if [ "$DRY" = 1 ]; then warn "$FAILS pre-flight check(s) failed; continuing because of --dry-run"; else die "$FAILS pre-flight check(s) failed, nothing changed"; fi
}

# ---------------------------------------------------------------- modes
do_transition() {
  preflight; gate
  wait_window
  local_give_up
  [ -n "${STATE_FILE:-}" ] || STATE_FILE="vote_history-$(pubkey_of local "$LOCAL_FUNDED_KEYPAIR").bin"   # dry-run without a file
  log "carrying $STATE_FILE to $PEER_USER@$PEER_HOST:$PEER_STATE_DIR/"
  run scp -p "${SSH_OPTS[@]}" "$LOCAL_STATE_DIR/$STATE_FILE" "$PEER_USER@$PEER_HOST:$PEER_STATE_DIR/"
  peer_take "$STATE_FILE"
  if [ "$DRY" = 0 ]; then
    local p_id; p_id="$(running_identity peer || true)"
    log "peer now reports identity ${p_id:-?}; this host $(running_identity local || echo '?')"
    [ "$p_id" = "$(pubkey_of local "$LOCAL_FUNDED_KEYPAIR")" ] || warn "peer does not report the funded identity yet, check it: ssh $PEER_USER@$PEER_HOST"
  fi
  log "done. Watch the peer vote (monitoring: Voting), this host shows Standby."
}
do_arm() {
  [ "$LOCAL_CLIENT" = agave ] || die "--arm applies to a client that takes the vote account from a start script; on Firedancer the vote account is in $LOCAL_CONFIG"
  [ -n "$LOCAL_START_SCRIPT" ] || die "$CONF: LOCAL_START_SCRIPT is empty (set start_script in the profile entry)"
  [ -f "$LOCAL_START_SCRIPT" ] || die "$LOCAL_START_SCRIPT does not exist"
  local unf_pk id; unf_pk="$(pubkey_of local "$LOCAL_UNFUNDED_KEYPAIR")"; id="$(running_identity local || true)"
  [ "$id" = "$unf_pk" ] || die "refusing to re-arm: this host runs identity ${id:-?} (not its unfunded key $unf_pk)"
  [ "$(readlink -f "$LOCAL_IDENTITY_LINK")" = "$(readlink -f "$LOCAL_UNFUNDED_KEYPAIR")" ] || die "refusing to re-arm: $LOCAL_IDENTITY_LINK does not point at the unfunded key"
  log "arming for '$NAME' (vote account $LOCAL_VOTE_ACCOUNT): $LOCAL_START_LINK -> $LOCAL_START_SCRIPT, restart $LOCAL_SERVICE"
  run as_user ln -sfn "$LOCAL_START_SCRIPT" "$LOCAL_START_LINK"
  if [ "$(id -u)" = 0 ]; then run systemctl restart "$LOCAL_SERVICE"; else run sudo systemctl restart "$LOCAL_SERVICE"; fi
  [ "$DRY" = 1 ] && { log "[dry-run] would wait for catch-up, then print the armed vote account"; return; }
  log "waiting for catch-up (Ctrl-C leaves the validator running)"
  local st; while :; do
    if st="$(caught_up local)"; then log "caught up: $st"; break; fi
    log "not yet: $st"; sleep 30
  done
  log "armed vote account: $(armed_vote_account local || echo '?')"
}
do_takeover() {
  local funded_pk unf_pk id vote st file
  funded_pk="$(pubkey_of local "$LOCAL_FUNDED_KEYPAIR")"; unf_pk="$(pubkey_of local "$LOCAL_UNFUNDED_KEYPAIR")"
  id="$(running_identity local || true)"; vote="$(armed_vote_account local || true)"
  [ "$id" = "$unf_pk" ] || die "this host runs identity ${id:-?}, not its unfunded key; take-over is for a standby"
  [ "$vote" = "$LOCAL_VOTE_ACCOUNT" ] || die "not armed for '$NAME': running vote account ${vote:-?}, expected $LOCAL_VOTE_ACCOUNT (node-transition.sh $NAME --arm)"
  file="$(state_file local "$funded_pk")"
  [ -z "$file" ] || die "$LOCAL_STATE_DIR/$file exists: use the normal transition from the active host, or remove the file if you know it is stale"
  st="$(caught_up local)" || die "not caught up: $st"
  log "caught up: $st"
  cat <<MSG
[transition] EMERGENCY TAKE-OVER of $funded_pk on this host, WITHOUT a vote history / tower file.
  Anza's preconditions, both are on you:
    1. the active host is SHUT DOWN (power it off if you cannot reach it), it must not vote again;
    2. this host has finalized slots past the active host's last vote.
  Taking the identity while the other host still votes is a double-vote (slashing) incident.
MSG
  if [ "$YES" != 1 ] && [ "$DRY" = 0 ]; then
    local answer; read -r -p "Type the funded pubkey to proceed, anything else to abort: " answer
    [ "$answer" = "$funded_pk" ] || die "aborted, nothing changed"
  fi
  local_take ""
  log "this host now reports identity $(running_identity local || echo '?')"
}
do_check() { preflight; log "$FAILS check(s) failed"; [ "$FAILS" = 0 ]; }

load_conf
if [ "$LOCAL_CLIENT" = firedancer ] && [ "$(id -u)" != 0 ] && [ "$MODE" != check ] && [ "$DRY" = 0 ]; then die "on a Firedancer host run this as root (sudo node-transition.sh ...)"; fi
case "$MODE" in
  transition) do_transition ;;
  check)      do_check ;;
  arm)        do_arm ;;
  takeover)   do_takeover ;;
esac
