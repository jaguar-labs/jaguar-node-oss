## MODIFIED Requirements

### Requirement: Wizard prompts only for validator-specific essentials
The wizard SHALL prompt for: validator name, cluster (`testnet`, `mainnet`, or `alpenglow`), validator identity pubkey (base58 or `gen` to defer generation to the host), vote account pubkey (base58, or `skip`/empty to defer — the host generates a vote-account keypair and the operator creates the account on-chain later), the disk configuration (via the selection-first assignment flow when unused disks are detected, else the classic layout prompt: `separate` or `single`, default `separate`, with the corresponding device(s)), validator log path, Jito enabled (and if yes: commission bps and block-engine region) — skipped and rendered disabled on `alpenglow`, which has no Jito — alpenglow's restart-sensitive values (`expected_shred_version`, `expected_bank_hash`, defaults from the presets with a check-latest warning) when that cluster is chosen, and XDP enabled (and if yes: NIC interface and retransmit cores). Every prompt SHALL show its default (where one exists) and accept Enter to keep it. All other playbook values SHALL come from the template's defaults without prompting.

#### Scenario: Operator accepts defaults
- **WHEN** the operator runs the wizard and presses Enter through optional prompts, providing only name, cluster, and pubkeys
- **THEN** a complete playbook is generated using the separate-disk paths with the sample profile's defaults and feature toggles (Jito on for testnet/mainnet, XDP off), plus the disk-setup script for the default devices

#### Scenario: Basic input validation
- **WHEN** the operator enters an obviously invalid value (empty validator name, cluster other than testnet/mainnet/alpenglow, a pubkey that is neither 32-44 base58 characters nor the deferral token, disk layout other than separate/single)
- **THEN** the wizard re-prompts with an error message instead of writing a broken playbook

#### Scenario: Deferred keys accepted
- **WHEN** the operator answers `gen` at the identity prompt and `skip` at the vote account prompt
- **THEN** the playbook is generated with both pubkey vars empty, and the next-steps output explains that the host generates both keypairs during provisioning and prints the on-chain `solana create-vote-account` command the operator must run afterwards

#### Scenario: Alpenglow skips Jito
- **WHEN** the operator selects `alpenglow`
- **THEN** no Jito prompts appear, the generated playbook has `jito.enabled: False`, and the shred-version/bank-hash prompts appear with preset defaults and a warning that they change on cluster restarts

### Requirement: Cluster choice supplies correct presets
Selecting a cluster SHALL auto-fill, without prompting: gossip entrypoints, known validators (empty for `alpenglow`), expected genesis hash, remote cluster RPC address, solana metrics database parameters, the dynamic port range (`8000-10000` for testnet/mainnet, `9000-12500` for alpenglow), and — when Jito is enabled — the cluster-appropriate block-engine URL, shred receiver address, tip payment/distribution program pubkeys, merkle root upload authority, and Jito NTP server.

#### Scenario: Testnet presets
- **WHEN** the operator selects `testnet`
- **THEN** the generated playbook contains the testnet entrypoints (`entrypoint*.testnet.solana.com:8001`), testnet genesis hash `4uhcVJyU9pJkvQyS88uRDiswHXSCkY3zQawwpjk2NsNY`, and testnet Jito endpoints if Jito is enabled

#### Scenario: Mainnet presets
- **WHEN** the operator selects `mainnet`
- **THEN** the generated playbook contains mainnet entrypoints, the mainnet genesis hash `5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d`, mainnet known validators, and mainnet Jito endpoints if Jito is enabled

#### Scenario: Alpenglow presets
- **WHEN** the operator selects `alpenglow`
- **THEN** the generated playbook contains the alpenglow IP entrypoints (`64.130.37.11:8000`, `213.239.141.16:8001`), genesis hash `HtRW7y9hJZaEBgH8cvUomQQjaXY5vM8J54nqbZJz7MjW`, remote RPC `http://185.8.106.234:8899`, metrics `db=alpenglow-testnet` with the public `ag` credentials, `dynamic_port_range: 9000-12500`, an empty known-validators list, and `jito.enabled: False`

#### Scenario: Existing clusters unchanged
- **WHEN** a testnet or mainnet playbook is regenerated with pre-change inputs
- **THEN** the output is byte-identical (the port-range token renders the previous constant)
