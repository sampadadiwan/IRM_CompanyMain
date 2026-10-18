# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **v1 is local** (decided 2026-10-18): Ravi's own Claude Code login, Claude Code's Bash sandbox, no
> Docker. The container is stage 2 (design › Delivery stages) and not in this task list.

## 1. Local sandbox and Claude Code guarantees (spike first)

- [ ] 1.1 Install `socat` (user, `sudo apt install socat`); verify `which bwrap socat` shows both
- [ ] 1.2 Spike the Claude Code guarantees the design relies on (LLD › Configuration and Rollout): Bash sandbox blocks network and writes outside the workspace and `state/`; `permissions.deny` blocks Read/Edit/Write on `state/**`, secrets and the settings file; hook `ask` overrides a saved allow; record results in design.md risks — stop and revisit the design if any fails
      **Result 2026-10-18:** deny rules and hook `ask` proven; the Bash sandbox fails on this box (design.md Risks) —
      choose an isolation option before 1.3
- [ ] 1.3 `onboarding_agent/claude/settings.json` and `onboarding_agent/bin/start` (creates `~/work/onboarding/<client>/` from the template, installs the workspace Gemfile, launches `claude` with `--settings`, `--add-dir`, `--strict-mcp-config`); verify `claude` starts in the workspace and `/mcp` lists `onboarding`
- [ ] 1.4 Write `features/client_onboarding/isolation.feature` (E11, X5, X6, X7 — asserting the settings: no network for Bash, deny rules for secrets, `state/`, checkout and settings file), each scenario with its `# ID — …` comment; run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding/isolation.feature` until green before starting phase 2

## 2. Onboarding tools: client, state, guards (⑥)

- [ ] 2.1 `AppClient`, `StateStore`, `bin/new_client` (LLD › Method Contracts, Schema Detail); verify a `get_entity` call against the dev app from a Ruby console outside Rails
- [ ] 2.2 `Guards` (fresh, sandbox, order) and `ImportOrder` with ID comments (E1–E4, E8, X1–X3); verify via phase feature
- [ ] 2.3 `bin/onboarding_mcp` with read tools and `update_entity_settings`, `upload_import`, `undo_import`; verify `claude mcp list` inside the container shows them
- [ ] 2.4 Audit every notifier an import can trigger for sandbox handling; record any that ignore it as app bugs in `.claude/skills/client-onboarding/api-gaps.md` (no app change)
- [ ] 2.5 `features/support/client_onboarding_server.rb` + `features/step_definitions/client_onboarding_steps.rb` (LLD › Test Plumbing) including `@stub_api_gaps`
- [ ] 2.6 Write `entity_guards.feature` (H1, E1, E2), `sandbox.feature` (H2, X1, X2), `import_order.feature` (E3, E4, E8), `imports.feature` (H3, H10, E17, X9, X10, X12), `api_gaps.feature` (X3, X4); run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding/{entity_guards,sandbox,import_order,imports,api_gaps}.feature` until green before starting phase 3

## 3. Approval gate (⑤)

- [ ] 3.1 `Gate.decide` and `hooks/pre_tool_use.rb` (LLD › Method Contracts); summary built from the file (type, rows, fund)
- [ ] 3.2 `grant_waiver` tool, never-waive list (undo, InvestorAccess, InvestorAdvisor)
- [ ] 3.3 Write `gate.feature` (H5, E5, E6, E7, X8); run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding/gate.feature` until green before starting phase 4

## 4. Mapping, check and reconcile

- [ ] 4.1 `Mapping` (column outcome + money `scale`) and `Reconciler#check_transform` (LLD › Method Contracts)
- [ ] 4.2 `Reconciler#reconcile` via JSON index endpoints, paise comparison, paged `account_entries` (LLD › Queries)
- [ ] 4.3 xlsx fixtures in `features/fixtures/client_onboarding/`
- [ ] 4.4 Write `check_transform.feature` (H8, E9, E10), `custom_fields.feature` (H6), `reconcile.feature` (H4, H7, E14, E15); run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding/{check_transform,custom_fields,reconcile}.feature` until green before starting phase 5

## 5. Failures, undo and resume

- [ ] 5.1 `get_import_result` (results file parse) and undo ownership check (X11)
- [ ] 5.2 Resume: progress summary on server start
- [ ] 5.3 Write `failures.feature` (E12, E13, E16, X11) and `resume.feature` (H9); run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding/{failures,resume}.feature` until green before starting phase 6

## 6. Skill, trial and sign-off

- [ ] 6.1 Update `.claude/skills/client-onboarding/` (SKILL.md tool names, workspace layout, learnings) to match what was built
- [ ] 6.2 Coverage check: every H/E/X ID in design.md equals the set of `# ID —` comments in `features/client_onboarding/`
- [ ] 6.3 Run all onboarding features: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/client_onboarding` until green
- [ ] 6.4 Trial on the dev box with the real client workbook (user)
- [ ] 6.5 QA: run qa-checklist.md and record sign-off (QA, not the apply agent)
