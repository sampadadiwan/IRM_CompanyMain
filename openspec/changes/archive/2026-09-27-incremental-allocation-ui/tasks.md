## 1. Data model

- [x] 1.1 Add migration creating `fund_formula_operations` (entity_id, fund_id, operation, status, requested_by_id, applied_by_id, plan/result/params json, error text, previewed_at, applied_at, timestamps; index `[fund_id, created_at]`). Follow the local schema-drift procedure (restore `schema.rb`/`schema_test.rb`, hand-insert the table, `db:clean_schema`). Verify: `git diff db/schema.rb` shows only the new table.
- [x] 1.2 Add `FundFormulaOperation` model: operations and statuses constants, belongs_to fund/entity/users, `active` scope (`previewing`/`applying`), stale detection (older than `STALE_RUN_HOURS`). Verify: `bin/rails runner` creates, reads and scopes a record for fund 342 inside a rolled-back transaction.

## 2. Incremental migration service refactor

- [x] 2.1 Introduce `IncrementalMigration::Plan` (edits, blockers, warnings, reseeds, fingerprint; `to_h`/`from_h`). Make `enable_plan(with_values:)` and `disable_plan` return it with no printing. Verify: runner on fund 342 shows plan hashes matching the current `enable!` dry-run content.
- [x] 2.2 Move `reseed_carry_forward` logic from the rake file into `reseed_plan(date:, formulas:)`, returning a Plan with old/new per folio. Verify: runner on fund 342 for 2026-03-31, seq 230–235 gives the same values as the current task's `DRY_RUN=true` output.
- [x] 2.3 Implement `apply!(plan)`: re-plan, compare fingerprint and recomputed reseed totals, raise `PlanChanged` on any difference, write in one transaction. Verify: in a rolled-back transaction, editing a formula between plan and apply raises `PlanChanged` and writes nothing; an unchanged plan applies.
- [x] 2.4 Add `IncrementalMigration::TextReport`. Rewrite `enable!`/`disable!`/`describe!` as plan → report → apply compositions. Rewrite `lib/tasks/incremental_allocation.rake` (including `reseed_carry_forward`) as thin wrappers. Verify: dry-run output of all four tasks on fund 342 is identical to before the refactor (saved before/after text diff), and `rubocop` passes.
- [x] 2.5 Add `FundAllocationActivity.busy?(fund)` (group run busy, recent blank/`Pending` run, active operation). Verify: runner shows false for fund 342, and true after inserting a `Pending` run in a rolled-back transaction.
- [x] 2.6 Refuse `FundsController#allocate` and the allocation run group preflight while an operation for the fund is `applying`. Verify: Cucumber scenario in 8.2 (a flash alert and no run created).

## 3. New check helpers

- [x] 3.1 Add `folio_shares_total(field_key)` to `CheckHelpers`: UDR-style codes used by the period's fund-level uploads and held investments, mapped to folio fields, each summing to 100 within tolerance. Verify: runner against run 1857 passes, and fails in a rolled-back transaction with one folio's `udr_2` changed.
- [x] 3.2 Add `unit_settings_present(keys)`. Verify: passes on fund 342; fails with `hurdle_rate` removed from Class D in a rolled-back transaction.
- [x] 3.3 Add `since_inception_matches_history(names, tolerance: 1.0)`, per folio and name, SQL aggregates only. Verify: passes for run 1857; fails with 500.00 added to one stored Since Inception entry in a rolled-back transaction.
- [x] 3.4 Extract a helper catalogue constant (signature plus purpose) used by the AI prompt. Document the three helpers in `docs/modules/allocation/allocation_run_checks.md`. Verify: the doc's helper list matches the constant.

## 4. Rule-based suggester

- [x] 4.1 Add `RunCheckSuggestions::Context` loading formulas, custom field forms, distinct uploaded `(name, entry_type, parent_type, level)`, folio field keys, unit types, unit settings and currencies with no `account_entries` row loads. Verify: runner on fund 342 prints the context; the SQL log shows only `DISTINCT`/aggregate queries on `account_entries`.
- [x] 4.2 Implement the `Suggestion` struct and rules `allowed_names`, `required_fields`, `deal_mapping` with evidence. Verify: runner on fund 342 yields the checks imported as seq 311–315 (same helper calls and lists).
- [x] 4.3 Implement rules `folio_shares`, `unit_settings`, `fx_rates`, `valuations`. Verify: runner on fund 342 yields `folio_shares_total(:fund_level_udr_code)`, `unit_settings_present(["catch_up", "hurdle_rate"])`, an FX check and a valuation warning.
- [x] 4.4 Implement rules `entries_allocated`, `portfolio_tie` (skipping sign-flipped columns) and `since_inception`. Verify: runner on fund 342 yields the post checks equivalent to seq 320–323, and excludes "Portfolio cost of sold excluding expenses".
- [x] 4.5 Mark suggestions whose formula text matches an existing check as already present, and validate each suggestion as an unsaved `FundFormula`. Verify: runner on fund 342 marks the imported equivalents already present, and every suggestion is `valid?`.
- [x] 4.6 Test-run suggestions with `RunChecks` against the latest successful run and store per-suggestion results; `not_tested` when there is no successful run. Verify: runner on fund 342 reproduces 12 pass / 1 FX fail.

## 5. AI suggester

- [x] 5.1 Implement `RunCheckSuggestions::AiSuggester`: prompt from the helper catalogue, blocked words, non-reporting formulas (truncated), existing suggestions and uploaded names; `LlmService.ruby_llm_chat(entity:).ask`, parsed as JSON; validation into accepted/rejected; errors captured. Verify: runner on fund 342 with a live key returns parsed suggestions (or a captured `ai_error`); the prompt size is logged.
- [x] 5.2 Feed accepted AI suggestions through the same already-present check and test run (4.5, 4.6). Verify: runner with a stubbed response containing one valid and one `delete`-containing formula stores one tested suggestion and one rejection.

## 6. Shared attribute builder

- [x] 6.1 Extract `FundFormulaAttributes.from_row`/`to_row` from `ImportFundFormula`, and make the importer use `from_row`. Verify: re-importing `tmp/fund_342_run_checks.xlsx` into a scratch fund in a rolled-back transaction creates the same 13 formulas as before.
- [x] 6.2 Add an xlsx writer for suggestions using `ImportFundFormula::STANDARD_HEADERS` and `to_row`. Verify: runner writes a file whose rows round-trip through `from_row` to the same attributes as Add selected.

## 7. Jobs, controller, policy, views

- [x] 7.1 Add `FundFormulaOperationJob(id, step)` running preview, apply, reseed and suggest steps. It sets statuses, timestamps, plan/result/error, and treats `PlanChanged` and busy as `refused`. Verify: `ImportUploadJob`-style `perform_now` via runner on fund 342 moves a preview to `previewed` with a stored plan.
- [x] 7.2 Add `FundFormulaOperationPolicy` (all actions `support?`) and routes for index/show/create/apply/add_suggestions/download_suggestions scoped by `fund_id`. Verify: `bin/rails routes | grep fund_formula_operations`, and a non-support request is refused (8.1).
- [x] 7.3 Add `FundFormulaOperationsController`: one active operation per fund under a fund row lock, stale active rows failed on create, busy guard on apply. Verify: Cucumber scenarios in 8.1.
- [x] 7.4 Build the incremental allocation page: current state, recommended steps (derived), history, and actions (preview on/off, recompute starting values with date). Verify: the page renders for fund 342 in dev showing "switched on", steps 1–3 done, and history.
- [x] 7.5 Build the plan/result view: edits (before/after/description), blockers, warnings, reseed table, apply button only when previewed and unblocked, Turbo frame polling while active. Verify: a dev preview for fund 342 switch-off shows seq 168 restore and polls until done.
- [x] 7.6 Build the suggestions view: grouped pre/post, source badge, evidence, test result and rows, severity toggle, "already present" state, AI request button, rejected list, Add selected, Download xlsx. Verify: a dev run on fund 342 shows the suggestions, and Download produces a file that imports cleanly.
- [x] 7.7 Rename the "Enable All" dropdown to "Actions" in `fund_formulas/_index.html.erb` and add the two support-only links. Verify: dev page as a support user and as a non-support user.

## 8. Cucumber coverage

- [x] 8.1 `features/fund/incremental_allocation_ui.feature`: menu visibility by role; non-support refusal; preview leaves data unchanged; blocked preview offers no apply; apply switches on with descriptions; changed plan refused; busy fund refused; switch off restores; recompute starting values; history listing.
- [x] 8.2 Scenario: an allocation run is refused while an operation is applying.
- [x] 8.3 `features/fund/run_check_suggestions.feature`: rule suggestions from formula patterns with evidence; repeatable; FX rule absent without currency; already present; test results including fail and not-tested; severity switch; Add selected; download → import round trip; AI suggestions with stubbed LLM (accepted, rejected, error); kept set on return.
- [x] 8.4 Scenarios for the three new helpers (pass and fail each) in `features/fund/allocation_run_checks.feature`.
- [x] 8.5 Scenario: rake dry run output matches the UI plan for the same fund.
- [ ] 8.6 Hand the full Cucumber command (with a random `TEST_ENV_NUMBER` and local Redis up) to the user to run; record results once they run it.

## 9. Docs

- [x] 9.1 Update `docs/modules/allocation/incremental_allocation_history.md` (F5: UI plus rake wrapper) and `docs/modules/allocation/incremental_allocation_validation.md` section 8 (checklist points at the UI). Verify: both reference the Actions menu flow.
- [x] 9.2 Write a support user guide for incremental allocation and run check suggestions, following the user-guide FAQ standard, with FAQs verified from code. Verify: `UserGuideLint` passes.
