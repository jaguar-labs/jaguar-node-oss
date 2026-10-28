# Design

## Context

See proposal.md for motivation. Current state and constraints:

- `node-transition.sh.j2` renders once per host with the funded key fixed to `funded-validator-keypair.json` and
  the peer IP left empty, to be edited in the installed file. On a shared standby, operators keep one hand-made
  copy per primary, differing only by the peer address and the funded key file (`<name>-funded-validator-
  keypair.json`), and switch `start-node.sh` by hand between `start-node-<name>.sh` variants before a transition,
  because the vote account and `--authorized-voter` are fixed at process start.
- Agave (`master`): `set-identity` loads `<ledger>/vote_history-<pubkey>.bin`, refuses otherwise unless
  `--do-not-require-vote-history`; `--require-tower` is accepted and ignored. State files are written by atomic
  rename. The Solana CLI (`solana catchup`) is on every Agave host of this repo.
- Firedancer hosts (`firedancer-support`): `identity.json -> staked|unstaked-identity.json`, a handoff directory,
  `fd-set-identity.sh staked [--vote-history-file F] [--do-not-require-vote-history] | unstaked`, which also moves
  the link; admin commands run as root; the vote account is fixed in the validator configuration, so a Firedancer
  host serves one validator.
- Two unconditional `state: link` tasks (node-base → funded, validator → unfunded) run in that order on every play.
- Nothing in the repo may name a validator, host or key; profiles are kept outside the repo.

## Goals / Non-Goals

**Goals:**
- One script, same bytes on every host, every client, every direction.
- Everything host-specific in configuration rendered by Ansible from the profile.
- The standby's "which validator am I armed for" state is checked, and changed, by the script.
- The emergency take-over is a scripted, gated mode.

**Non-Goals:**
- Automatic failover or any decision taken by monitoring.
- Reconciling the three managers of a shared standby's start scripts (this repo, the Hexis role, hand edits);
  the script only reads which start script `start-node.sh` points at and repoints it on `--arm`.
- Arming a Firedancer standby for another vote account (its vote account lives in its configuration).

## Decisions

### D1. Configuration-driven script, one file per name

`node-transition.sh [<name>] [--check | --arm | --take-over | --dry-run | --now]` sources
`/etc/node-transition.d/<name>.conf`; with a single file the name is optional. The file is shell `KEY=value`,
no secrets, 0644, rendered from one entry of `transition_peers`:

```
NAME
LOCAL_CLIENT=agave|firedancer  LOCAL_USER  LOCAL_SERVICE  LOCAL_STATE_DIR (ledger | base path)
LOCAL_FUNDED_KEYPAIR  LOCAL_UNFUNDED_KEYPAIR  LOCAL_IDENTITY_LINK  LOCAL_VOTE_ACCOUNT
LOCAL_START_SCRIPT  LOCAL_START_LINK (agave only)  LOCAL_ADMIN (agave-validator | firedancer binary)
LOCAL_CLI_BIN (agave: solana / solana-keygen dir)  LOCAL_IDENTITY_SCRIPT  LOCAL_CONFIG (firedancer only)
LOCAL_RPC_PORT  LOCAL_METRICS_PORT (firedancer only)  CLUSTER_RPC_URL (optional, catch-up comparison)
PEER_HOST  PEER_USER  PEER_CLIENT  PEER_STATE_DIR (ledger | handoff)  PEER_FUNDED_KEYPAIR  PEER_UNFUNDED_KEYPAIR
PEER_IDENTITY_LINK  PEER_ADMIN  PEER_CLI_BIN  PEER_IDENTITY_SCRIPT  PEER_CONFIG  PEER_VOTE_ACCOUNT  PEER_RPC_PORT
PEER_METRICS_PORT  PEER_SUDO=yes|no
```

Why: the same script can run on either client because every client-specific path is data; a shared standby is
just several files; the repo never names anything. Alternative rejected: Jinja-rendered script per peer (today's
model, one file per peer, unmaintainable and un-shareable with the Firedancer repo).

### D2. Client operations behind four functions

`wait_window`, `set_identity <key> [state file]`, `move_link <key>`, `state_file <pubkey>`, each with an Agave
and a Firedancer body, run locally or through `ssh PEER_USER@PEER_HOST` (prefixed with `sudo -n` when
`PEER_SUDO=yes`). Agave: `wait-for-restart-window`, `set-identity [--require-tower] <key>` in `LOCAL_STATE_DIR`,
`ln -sfn`, `vote_history-P.bin` else `tower-1_9-P.bin`. Firedancer: `firedancer wait`, `fd-set-identity.sh
staked --vote-history-file F | unstaked` (which moves the link itself), same file names in the base path. The
destination of the copied file is `PEER_STATE_DIR` with the name kept, owned by `PEER_USER`, because Agave reads
only its ledger and Firedancer reads any path.

### D3. Pre-flight (`--check`, and always before a transition)

ssh to the peer in batch mode; funded key sums equal and unfunded sums different; local link → funded and running
identity = funded pubkey; peer link → unfunded and peer running identity = unfunded pubkey; peer armed for
`PEER_VOTE_ACCOUNT` (Agave: process command line; Firedancer: its configuration); state file present locally;
peer caught up (Agave: `solana catchup`; Firedancer: root distance from its metrics); when `PEER_CLIENT=
firedancer`, `sudo -n PEER_ADMIN --help` succeeds over ssh; both client versions printed. Any failure stops
before any identity change.

### D4. State file detection

Vote history first, tower as fallback, refuse when neither exists. `--require-tower` is added on the peer only
when a tower file was carried, so older Tower builds keep their guard and new builds ignore the no-op.
Alternative rejected: a `consensus` variable, wrong on activation day.

### D5. `--arm <name>` on a standby

Refuse unless the running identity is the unfunded key. Point `start-node.sh` at `LOCAL_START_SCRIPT`, restart
`LOCAL_SERVICE`, wait for catch-up, print the armed vote account. On a Firedancer host the mode refuses and
explains that the vote account is configuration. Why in the script: the standby cannot take an identity it is
not armed for, and today the repoint and restart are remembered steps.

### D6. `--take-over <name>` on a standby

No ssh. Refuse unless armed for the name, caught up, and no state file for the funded pubkey is present locally
(then the normal path applies). Print the two preconditions from Anza's guide; the operator types the funded
pubkey (or `--yes`). Agave: `set-identity --do-not-require-vote-history <funded>` under Alpenglow,
`set-identity <funded>` under Tower; Firedancer: `fd-set-identity.sh staked --do-not-require-vote-history`.
Then `move_link`.

### D7. Symlink created once

Keep the link creation in `create_unfunded_validator_keypair.yaml` only, guarded by a `stat`, target unfunded;
delete the task in `configure_node.yaml`. A fresh host boots non-voting until a transition to it. Alternative
rejected: a `voting_role` profile variable, which on a host that has failed over would re-arm double voting at
the next run.

### D8. One source, two installers

The script is `roles/validator/files/node-transition.sh`, copied as today to `{{ solana_home }}`;
`firedancer-support` fetches the same file from this public repo at a pinned commit with a sha256 and installs it
under `/usr/local/sbin`. Why not a shared role: the sibling repos share conventions, not code; a pinned fetch is
the pattern already used for the telemetry collector.

### D9. Alpenglow start script

Add `--authorized-voter` for parity with the standard script and remove the startup `--do-not-require-vote-history`.
The flag dates from the pre-activation test cluster; with Alpenglow live everywhere a start script that skips the
vote history check is a double-vote risk on any cluster, and the Anza guide reserves the flag for the gated
emergency `set-identity` (D6). No mainnet assertion is needed once the flag is gone. The template itself only
differs from the standard one by its restart pins now; retiring it, `build-alpenglow.sh` and the `alpenglow`
toggle is a separate change.

## Risks / Trade-offs

- [Hosts whose link was flipped by a past run] → README upgrade note: `readlink` once per host; `--check` prints
  both links.
- [`--take-over` while the primary is merely unreachable] → confirmation text states the slashing consequence;
  the mode refuses when a fresh local state file exists.
- [Firedancer peer needs passwordless `sudo` for one command] → provided by `firedancer-support` for the peer's
  ssh user; `--check` verifies it and the script prints the command instead of running it when it fails.
- [Other managers repoint `start-node.sh`] → `--check` prints the current target and the armed vote account; the
  reconciliation is a separate change.
- [Configuration drift between the two repos' renderers] → the key list in D1 is the contract; both renderers
  are tested against the same sample in their drills.

## Migration Plan

1. Merge; syntax check and CI static checks pass. The script is exercised before any host sees it with a local
   simulation (two directories, fake `ssh`/`scp`/`agave-validator`/`firedancer`/`fd-set-identity.sh`/`curl`/
   `systemctl`/`sudo` shims on `PATH`, `NODE_TRANSITION_CONF_DIR` pointing at scratch configurations): the four
   client combinations in dry-run and for real, the tower variant, `--arm`, every refusal of `--take-over` and
   the gated take-over itself.
2. Re-run the playbook on every host of each pair or group; verify link targets unchanged on voting hosts;
   delete hand-copied script variants once their configuration entries exist.
3. Drill on a testnet pair: normal transition both ways, `--arm`, `--take-over` up to the prompt.
4. Rollback: previous templates and the hand-copied variants, which nothing deletes automatically.
