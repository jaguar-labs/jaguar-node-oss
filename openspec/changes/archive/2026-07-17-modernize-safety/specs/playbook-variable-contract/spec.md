## ADDED Requirements

### Requirement: Every template-time variable is defined and asserted
Every variable referenced by a template or task that has no role default SHALL be defined in the playbook `vars` and asserted in `pre_tasks` with a `fail_msg`. In particular `entrypoints` — currently referenced by `roles/validator/templates/start-node.sh.j2`, `start-node-jito.sh.j2`, and `roles/rpc/templates/start-node.sh.j2` but defined nowhere — SHALL be defined in the sample playbook as the official testnet entrypoint list, alongside `known_validators`.

#### Scenario: Fresh run without -e overrides
- **WHEN** the operator runs `playbooks/sample-testnet-profile.yaml` with only inventory and vault inputs
- **THEN** all start-node templates render successfully because `entrypoints` is defined in playbook vars

#### Scenario: Operator removes a required variable
- **WHEN** `entrypoints` (or any asserted variable) is undefined at run time
- **THEN** the run fails in `pre_tasks` with a `fail_msg` naming the missing variable, before any role executes

### Requirement: The assertion block is free of duplicates and tautologies
The `pre_tasks` assertion list SHALL contain each variable at most once, and no assertion SHALL restate its own `when` guard. The current duplicate `secrets_path` and `dynamic_port_range` entries and the `jito.enabled | bool` assertion gated on `when: jito.enabled | bool` are removed.

#### Scenario: Jito disabled
- **WHEN** `jito.enabled` is false
- **THEN** the jito variable assertions are skipped entirely and the play proceeds

#### Scenario: Jito enabled with a missing jito variable
- **WHEN** `jito.enabled` is true and e.g. `jito.block_engine_url` is undefined
- **THEN** the run fails in `pre_tasks` identifying the missing jito variable
