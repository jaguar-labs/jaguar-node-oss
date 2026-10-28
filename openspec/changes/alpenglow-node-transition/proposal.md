# Proposal

## Why

Anza's failover guide changed with Alpenglow: the file to carry is `vote_history-<IDENTITY>.bin`, `set-identity`
requires it by default, and `--do-not-require-vote-history` is the gated escape when the primary is dead. Our
`node-transition.sh` still looks for `tower-1_9-<pubkey>.bin` and exits before doing anything when it is absent,
`--require-tower` is now a deprecated no-op in Agave, and the script only knows how to talk to another Agave. The
fleet it must serve is no longer uniform: a shared standby stands in for several primaries, each with its own
funded key, vote account and start script, and primaries are moving to Firedancer (`firedancer-support`). Today
that is handled with hand-copied variants of the script on the standby, outside any automation.

## What Changes

- `node-transition.sh` becomes one client-agnostic script, driven by a per-name configuration file rendered by
  Ansible, used unchanged on Agave and Firedancer hosts and in both directions of a mixed pair. The source lives
  in this repo as a plain file (no Jinja); `firedancer-support` installs the same file from a pinned commit.
- The peers a host can hand over to are declared in the host's profile (`transition_peers`, a list); nothing in
  the repo names a validator, a host or a key. A standby serving several primaries gets one configuration per
  name; a primary gets one.
- The script detects the consensus state file (vote history first, tower as fallback), carries it, and drops
  `--require-tower` unless a tower file was carried.
- New modes: `--check` (pre-flight only), `--arm <name>` (standby: point the start script at the named
  validator's, restart, wait for catch-up) and `--take-over <name>` (standby, primary unreachable: gated
  `--do-not-require-vote-history`).
- **BREAKING** the `validator-keypair.json` symlink is created only when absent (pointing at the unfunded key) and
  never moved by the playbook. Today `node-base` links it to the funded key and the `validator` role re-links it to
  the unfunded key on every run, so a full run on a voting host silently arms a non-voting restart.
- `start-node-alpenglow.sh` gains `--authorized-voter` and loses its startup `--do-not-require-vote-history`:
  Alpenglow is live on every cluster, so the only remaining difference with the standard script is the bank hash
  and shred version pins, and the flag would let a node vote without its history after a botched failover. The
  separate template is now obsolete; retiring it is a follow-up change.

## Capabilities

### New Capabilities
- `node-transition`: the voting hand-over between two hosts of any client mix, driven by named per-host
  configuration; the identity symlink as operational state; arming a shared standby; the gated emergency
  take-over.

### Modified Capabilities
- `alpenglow-cluster-support`: the start script flag set gains `--authorized-voter` and drops
  `--do-not-require-vote-history`.

## Impact

- `roles/validator/files/node-transition.sh` (new, replaces `templates/node-transition.sh.j2`),
  `roles/validator/templates/node-transition.conf.j2` (new), `roles/validator/tasks/utils_scripts.yaml`,
  `roles/validator/tasks/create_unfunded_validator_keypair.yaml`, `roles/node-base/tasks/configure_node.yaml`,
  `roles/validator/defaults/main.yaml` (`transition_peers: []`), `roles/validator/templates/
  start-node-alpenglow.sh.j2`, `playbooks/sample-testnet-profile.yaml` (placeholder entry), `bin/new-playbook.sh` (optional prompt), README, CLAUDE.md.
- Hosts: `~/node-transition.sh` is replaced and `/etc/node-transition.d/<name>.conf` appears; hand-copied
  variants on a shared standby become configuration entries and can be deleted; the symlink is no longer touched
  by the playbook, so operators check it once after the upgrade.
- `firedancer-support` (change `align-failover-with-alpenglow`) installs the same script and renders the same
  configuration format; the contract between the two is the configuration keys, the state file name, the
  destination directory per client, and the one admin command a Firedancer host exposes to its peer.
