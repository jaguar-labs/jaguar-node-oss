# Tasks

## 1. Symlink as operational state

- [x] 1.1 Remove the funded-key link task from `roles/node-base/tasks/configure_node.yaml` and guard the link task
      in `roles/validator/tasks/create_unfunded_validator_keypair.yaml` with a `stat` so it runs only when
      `validator-keypair.json` is absent; verify with a local run on a scratch `secrets_path` that the first run
      links to unfunded and that a link pointed by hand at the funded key survives a second run
- [x] 1.2 Add the upgrade note to README (one-time `readlink` per host) and the rule to CLAUDE.md's "Symlink
      identity switching" line; verify the playbook syntax check and the CI static checks pass

## 2. Configuration and installer

- [x] 2.1 Add `transition_peers: []` to the validator role defaults with the entry structure from design D1
      documented in the sample profile with placeholder names only; add `templates/node-transition.conf.j2` and a
      task rendering `/etc/node-transition.d/<name>.conf` (0644, root) per entry and removing files for names no
      longer declared; verify a scratch run with two placeholder entries produces two files with every D1 key
      and no undefined variable
- [x] 2.2 Replace `templates/node-transition.sh.j2` by `files/node-transition.sh` (no Jinja) installed to
      `{{ solana_home }}` as today, and add a pre-task assertion that `transition_peers` entries have the required
      keys; verify `grep -rn` for validator, host or key names in `roles/` and `playbooks/` returns only the
      placeholders of the sample profile

## 3. node-transition.sh

- [x] 3.1 Implement configuration loading (name argument, single-file default), the four client operations of
      design D2 with local and ssh execution, and `--dry-run` printing every command; verify `bash -n` and a dry
      run against a scratch configuration for each of the four client combinations prints the sequences of the
      spec's hand-over scenarios
- [x] 3.2 Implement `--check` and the pre-flight of design D3; verify against a scratch peer (two local users on
      one machine are enough) that each failing condition stops the script with nothing changed and names the
      condition
- [x] 3.3 Implement state file detection per design D4 and the `--require-tower` rule; verify with a scratch state
      directory holding each file in turn that the chosen file and the remote command match the spec scenarios
- [x] 3.4 Implement `--arm` per design D5 (repoint `start-node.sh`, restart, catch-up wait, refusals); verify the
      dry run on a scratch configuration and the refusal when the running identity is funded or the local client
      is Firedancer
- [x] 3.5 Implement `--take-over` per design D6; verify the dry run shows the refusal when a state file exists
      locally or the host is not armed, and the full sequence otherwise, with the Alpenglow and Tower command
      variants

## 4. Alpenglow start script

- [x] 4.1 Add `--authorized-voter {{ secrets_path }}/funded-validator-keypair.json` to
      `start-node-alpenglow.sh.j2`; verify the rendered script against the spec scenario
- [x] 4.2 Remove `--do-not-require-vote-history` from `start-node-alpenglow.sh.j2` (no mainnet assertion needed
      once the flag is gone); verify the rendered script no longer contains the flag and the profile pre-tasks
      pass with alpenglow enabled on `testnet`

## 5. Drill

- [ ] 5.1 On a testnet pair, declare the peers in both profiles, run the playbooks, delete the hand-copied script
      variants, and run `--check` from both sides; verify every check is green and the configurations contain
      the expected names
- [ ] 5.2 Run the normal transition both ways with the real peer; verify the receiving node votes within two
      leader windows, the giving node shows standby in monitoring, and both links match the running identities
- [ ] 5.3 Run `--arm` for a second name on the standby and `--take-over` up to the confirmation prompt (answer
      no); verify the armed vote account changed and no identity changed; record timings and surprises in
      design.md and run `openspec validate alpenglow-node-transition --strict`
- [ ] 5.4 Publish the commit that `firedancer-support` pins and record its sha256 in that repo's change; verify
      `curl` of the raw file at that commit matches the local file
- [ ] 5.5 After the `.bak` fix (2026-10-30): publish the commit, bump `node_transition_commit` / sha256 in
      firedancer-support, reinstall on the Firedancer hosts first (the only ones that rename the file), then the Agave
      hosts at convenience; verify a Firedancer -> Agave `--dry-run` shows the `.bak` source and the plain destination
