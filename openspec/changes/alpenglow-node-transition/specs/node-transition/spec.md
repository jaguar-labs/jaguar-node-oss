# Spec Delta

## Purpose

Defines the voting hand-over between two validator hosts of any client mix, driven by per-host named
configuration, the identity symlink as operational state, the arming of a shared standby, and the emergency
take-over when the active host is unreachable.

## ADDED Requirements

### Requirement: One script, configured per name

The transition tooling SHALL be a single script, identical on every host whatever its client, that reads a named
configuration file for everything host-specific: local client, user, state directory, key files, identity link,
vote account, start script, admin command, and the same set for the peer. The repository SHALL NOT contain any
validator, host or key name; a host's names SHALL come from its profile. A host SHALL be able to hold several
named configurations.

#### Scenario: Shared standby with several primaries
- **WHEN** a host's profile declares several peers
- **THEN** one configuration per name is rendered and the script acts on the name given on its command line

#### Scenario: Single configuration
- **WHEN** a host holds exactly one configuration
- **THEN** the script runs without a name argument

#### Scenario: Same script on both clients
- **WHEN** the script installed on a Firedancer host and the one installed on an Agave host are compared
- **THEN** they are byte-identical

### Requirement: Pre-flight stops before any change

Before changing any identity, and on demand as a check-only mode, the tooling SHALL verify: the peer is
reachable non-interactively; the funded keys are identical and the unfunded keys differ; the local link and
running identity are the funded key and the peer's are the unfunded key; the peer is armed for the vote account;
the state file for the funded identity exists locally; the peer is caught up; and, for a Firedancer peer, the
peer's take-over command is runnable. Any failure SHALL stop the tooling with nothing changed.

#### Scenario: Peer not armed
- **WHEN** the peer runs with a vote account other than the one configured for the name
- **THEN** nothing changes and the output names the arming mode

#### Scenario: Check-only mode
- **WHEN** the operator runs the check-only mode
- **THEN** every verification result is printed, including both link targets and both client versions, and no
  identity changes

### Requirement: Consensus state file is detected, not assumed

The transition SHALL carry the state file that exists for the funded identity in the local state directory: the
vote history file under Alpenglow, otherwise the tower file, and SHALL refuse when neither exists.

#### Scenario: Alpenglow
- **WHEN** the state directory holds `vote_history-<funded pubkey>.bin`
- **THEN** that file is carried and the peer takes the identity without a tower requirement

#### Scenario: Tower
- **WHEN** the state directory holds only `tower-1_9-<funded pubkey>.bin`
- **THEN** that file is carried and an Agave peer is asked to require it

### Requirement: Hand-over works in both directions of any client mix

The tooling SHALL give up the identity locally, place the state file where the peer's client reads it, and take
the identity on the peer, using each client's own commands: an Agave side uses its validator admin command and
moves its link; a Firedancer side uses its identity script, which moves its own link. An Agave peer SHALL receive
the file in its ledger under the original name, owned by its validator user; a Firedancer peer SHALL receive it
in its handoff directory.

#### Scenario: Agave active, Firedancer peer
- **WHEN** the transition runs on an Agave host whose configured peer is Firedancer
- **THEN** the local node switches to its unfunded key, the file lands in the peer's handoff directory, the
  peer's identity script takes the funded key with that file, and the peer reports the funded identity

#### Scenario: Firedancer active, Agave peer
- **WHEN** the transition runs on a Firedancer host whose configured peer is Agave
- **THEN** the local node switches to its unstaked key, the file lands in the peer's ledger under its name, the
  peer's admin command takes the funded key, its link moves, and the peer reports the funded identity

#### Scenario: Same client both sides
- **WHEN** both hosts run the same client
- **THEN** the sequence is the same with that client's commands on both sides

### Requirement: Identity symlink is operational state

The playbook SHALL create the identity symlink only when it does not exist, pointing at the unfunded key, and
SHALL never change an existing symlink. Only operators and the transition tooling move it.

#### Scenario: Fresh host
- **WHEN** a host is provisioned for the first time
- **THEN** the symlink points at the unfunded key and the validator does not vote until a transition to it

#### Scenario: Re-run on the voting host
- **WHEN** the playbook re-runs on a host whose symlink points at the funded key
- **THEN** the symlink still points at the funded key afterwards

### Requirement: Arming a standby

On a host whose client takes the vote account from a start script, an arming mode SHALL point the start script at
the named validator's, restart the service, and wait for catch-up. It SHALL refuse while the host runs a funded
identity, and on a client whose vote account is configuration it SHALL refuse and say so.

#### Scenario: Standby armed for another name
- **WHEN** the operator arms a standby for a name while it runs the unfunded key
- **THEN** after the mode completes the process runs with that name's vote account and reports caught up

#### Scenario: Arming a voting host
- **WHEN** the operator arms a host that runs a funded identity
- **THEN** nothing changes and the refusal names the running identity

### Requirement: Emergency take-over is gated

A take-over mode run on the standby SHALL exist for the case where the active host is unreachable. It SHALL
proceed only when the standby is armed for the name, caught up, holds no state file for the funded identity, and
after the operator confirms that the active host is powered off.

#### Scenario: Primary dead, standby ready
- **WHEN** the operator runs the take-over on an armed, caught-up standby with no local state file and confirms
- **THEN** the standby takes the funded identity without a state file and its link points at the funded key

#### Scenario: Standby behind
- **WHEN** the standby is behind the cluster
- **THEN** the take-over refuses and prints the catch-up status

#### Scenario: State file already local
- **WHEN** a state file for the funded identity exists locally
- **THEN** the take-over refuses and points at the normal transition, which uses that file
