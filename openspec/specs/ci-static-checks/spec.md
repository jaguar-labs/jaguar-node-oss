# ci-static-checks Specification

## Purpose
TBD - created by syncing change `add-ci-guardrails`. Defines the GitHub Actions static verification surface: yamllint, ansible-lint, and playbook syntax checks that run in CI instead of on operator controllers.

## Requirements

### Requirement: CI runs lint and syntax checks on every push and pull request
A GitHub Actions workflow SHALL run on every push and pull request, executing: `yamllint` over the repo, `ansible-lint` with the committed `.ansible-lint` config, and `ansible-playbook --syntax-check` for every playbook under `playbooks/`. All Ansible execution for verification purposes SHALL happen in CI, never on operator controllers.

#### Scenario: Clean commit
- **WHEN** a commit satisfying all configured rules is pushed
- **THEN** the workflow passes and the README badge reports green

#### Scenario: Broken playbook structure
- **WHEN** a commit introduces a YAML syntax error or references a nonexistent role
- **THEN** the syntax-check job fails and blocks the PR (verified: a nonexistent role fails the job; note `--syntax-check` does NOT validate that `vars_files` targets exist — that class of error only surfaces at run time)

#### Scenario: Vaulted secrets during syntax-check
- **WHEN** the playbook loads an encrypted vault file via `vars_files`
- **THEN** CI supplies a dummy vault password/file sufficient for `--syntax-check` to parse, without any real secret present in the repository or CI logs

### Requirement: Lint configuration is explicit about its debt
The `.ansible-lint` config SHALL target the `production` profile, and every rule the current codebase does not yet satisfy SHALL be listed in `skip_list` or `warn_list` with a comment naming the modernization track that will remove it. New violations of non-skipped rules SHALL fail CI.

#### Scenario: Day-one green build
- **WHEN** CI runs on the codebase immediately after this change lands
- **THEN** ansible-lint passes, with pre-existing violations covered only by the documented skip/warn lists

#### Scenario: Idiom-sweep track lands
- **WHEN** a later change fixes a class of violations (e.g. converts `with_items` to `loop:`)
- **THEN** the corresponding skip_list entry is removed in the same change, so the rule enforces from then on
