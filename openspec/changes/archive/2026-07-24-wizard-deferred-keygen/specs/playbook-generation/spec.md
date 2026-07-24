## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet` or `mainnet`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), disk layout (`separate`, `single`, or `manual`, default `separate`), the disk shape and device(s) for the chosen layout (three devices for `separate`, one for `single`; `manual` first asks which of those two shapes the operator prepared, then the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region), and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk layout with the sample profile's default disk devices, paths, and feature toggles (Jito on, XDP off)

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet, a pubkey that is neither 32-44 base58 characters nor the deferral token, disk layout other than separate/single/manual)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

#### Scenario: Deferred keys accepted
- **WHEN** the operator answers `gen` at the identity prompt and `skip` at the vote account prompt
- **THEN** the playbook is generated with both pubkey vars empty, and the next-steps output explains that the host generates both keypairs during provisioning and prints the on-chain `solana create-vote-account` command the operator must run afterwards
