## ADDED Requirements

### Requirement: Collections are declared and pinned in requirements.yml
The repository SHALL contain a `requirements.yml` declaring every Ansible collection the roles use (`community.general`, `ansible.posix`) with explicit version constraints, and documentation SHALL install dependencies via `ansible-galaxy collection install -r requirements.yml` rather than ad-hoc install commands.

#### Scenario: Fresh environment setup
- **WHEN** an operator or CI job runs `ansible-galaxy collection install -r requirements.yml`
- **THEN** all collections referenced by any role task (e.g. `community.general.filesystem`, `community.general.cargo`, `ansible.posix.sysctl`) are installed at a version satisfying the pins

#### Scenario: Role uses an undeclared collection
- **WHEN** a task references a collection absent from `requirements.yml`
- **THEN** CI's ansible-lint/syntax-check job fails, surfacing the missing declaration before merge
