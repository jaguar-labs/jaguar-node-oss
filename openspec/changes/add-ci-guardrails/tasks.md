# Tasks: add-ci-guardrails

## 1. Dependency pinning

- [x] 1.1 Grep all roles for collection-namespaced modules (`community.general.*`, `ansible.posix.*`, any others) to build the definitive dependency list
- [x] 1.2 Create `requirements.yml` with version ranges for each collection, chosen against the ansible-core version CI will pin
- [x] 1.3 Update README: replace the manual `ansible-galaxy collection install community.general` step with `ansible-galaxy collection install -r requirements.yml`

## 2. Lint configuration

- [x] 2.1 Create `.yamllint`: default base, line-length relaxed, truthy/comment rules matched to existing repo style (2-space indent, `yes`/`no` currently used in places)
- [x] 2.2 Create `.ansible-lint`: `profile: production`, `skip_list`/`warn_list` entries for each rule class the codebase currently violates, each with a comment naming the future track that removes it (fqcn → idiom-sweep, no-changed-when → idiom-sweep, etc.)
- [x] 2.3 Run both linters locally (linters only — not ansible-playbook) and iterate the configs until clean

## 3. CI workflow

- [x] 3.1 Create `.github/workflows/ci.yaml` with three jobs (yamllint, ansible-lint, syntax-check) triggered on push and pull_request, with pinned ansible-core and ansible-lint versions
- [x] 3.2 Syntax-check job: install collections from `requirements.yml`, generate a dummy `vault/secrets.yaml` from `vault/secrets.example.yaml` keys if the real (encrypted) one is absent, then run `ansible-playbook --syntax-check` over `playbooks/*.yaml` with a dummy vault password file
- [ ] 3.3 Push the branch and iterate until all three jobs are green (CI is the execution surface — no controller runs)

## 4. README corrections

- [x] 4.1 Fix the quick-start: point at the real playbook (`playbooks/sample-testnet-profile.yaml`) instead of the nonexistent `full-validator-mainnet-profile.yaml`, and correct the clone URL to this repo
- [x] 4.2 Add the CI status badge

## 5. Verification

- [ ] 5.1 Confirm a deliberately broken YAML file on a scratch branch fails yamllint in CI
- [ ] 5.2 Confirm an undefined-variable-style playbook error (e.g. missing vars_files target) fails the syntax-check job
- [ ] 5.3 Confirm the main branch build is green and the badge renders in the README
