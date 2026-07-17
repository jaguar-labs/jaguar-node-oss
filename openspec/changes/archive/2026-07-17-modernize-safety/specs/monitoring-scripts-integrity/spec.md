## ADDED Requirements

### Requirement: Every deployed monitoring script is importable and runnable
Every Python file listed in the upload loop of `roles/monitoring/tasks/install_monitoring_script.yaml` SHALL import successfully and execute without `TypeError`/`ImportError` against the deployed module set. The three scripts calling `measurement_from_fields(name, info, config)` with three positional arguments (`output_validators.py`, `output_validators_info.py`, `output_gossip.py`) SHALL be fixed to match the signature `measurement_from_fields(name, data, tags, config, legacy_tags=None)`.

#### Scenario: Fixed output scripts execute
- **WHEN** `output_starter.sh output_validators` (or `output_gossip`, `output_validators_info`) runs inside the deployed venv
- **THEN** the script calls `measurement_from_fields` with an explicit tags dict and the config in the correct positional slot, and emits InfluxDB-line JSON without raising

#### Scenario: Static import check
- **WHEN** every uploaded `.py` file is compiled/imported in a checkout (e.g. `python3 -m py_compile` plus an import smoke test with a stub `monitoring_config`)
- **THEN** no file references a module that does not exist in the upload set

### Requirement: Unreferenced monitoring code is removed
Files in `roles/monitoring/files/` that are neither in the upload list nor imported by an uploaded file SHALL be deleted, and files in the upload list that cannot run SHALL be either fixed or removed from both the list and the repo. Specifically: `validator_monitoring.py` (imports nonexistent `validator_monitoring_library` and `validator_monitoring_config`) is deleted and removed from the upload list; `tds_info.py`, `measurement_tds_info.py`, and `output_tds_measurements.py` (never uploaded, call an external kyc endpoint) are deleted.

#### Scenario: Upload list matches repo contents
- **WHEN** the upload list in `install_monitoring_script.yaml` is compared against `roles/monitoring/files/`
- **THEN** every listed file exists, every existing file is either listed or imported by a listed file, and no listed file fails to import

### Requirement: Orphaned task files with security impact are removed
Task files never imported by any role `main.yaml` SHALL be deleted rather than left dormant. Specifically: `roles/common/tasks/ansible_user.yaml` (grants `%ansible` NOPASSWD ALL sudo and injects a control-node SSH key) and `roles/monitoring/tasks/install_telegraf_rpc.yaml` plus `roles/monitoring/templates/telegraf.rpc.conf.j2` (Telegraf pinned to 1.13.0 from 2019, plaintext TimescaleDB credentials).

#### Scenario: No dormant privileged task files
- **WHEN** the repo is searched for task files not reachable from any role `main.yaml`
- **THEN** none remain, and in particular no unreachable file contains a NOPASSWD sudoers edit

#### Scenario: Host behavior unchanged by deletions
- **WHEN** the playbook runs after the deletions
- **THEN** the set of tasks executed on hosts is identical to before (the deleted files were never imported), except that the three fixed output scripts now run correctly if invoked
