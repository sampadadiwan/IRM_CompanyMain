# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Traceability (every phase):** each Cucumber scenario carries a comment `# <ID> — <Happy path | Edge case | Error case>: <scenario>` naming its design.md worked example; code implementing a path names the IDs it serves in a comment. Every run uses a fresh `TEST_ENV_NUMBER=$RANDOM` with Redis up on 6379.

## 1. Schema, models and the calculator

- [x] 1.1 Create the migration for the six tables in [lld Schema Detail](lld.md#schema-detail) (`financial_statement_settings`, `_definitions`, `_accounts`, `_mapping_rules`, `_layout_rows`, `financial_statements`, `_mapping_suggestions`) with every listed index and FK; run `db:migrate`, then restore `db/schema.rb`/`db/schema_test.rb`, hand-insert the tables and run `db:clean_schema`. Verify: `git diff db/schema.rb` shows only the new tables.
- [x] 1.2 Add models `FinancialStatementSetting`, `FinancialStatementDefinition`, `FinancialStatementAccount`, `FinancialStatementMappingRule`, `FinancialStatementLayoutRow` with validations, enums and limits per [lld Schema Detail](lld.md#schema-detail) and `Fund has_many … dependent: :destroy`. Verify: `rails runner` creates one of each for a dev fund and duplicate names/keys raise.
- [x] 1.3 Add `FinancialStatementSetup.ensure!(fund)` ([lld Method Contracts](lld.md#method-contracts)): setting, three core definitions, statement `FundFormula` (`TYPES` += `GenerateFinancialStatementLines`, tag "Financial Statements", last sequence). Verify: calling it twice leaves one of each.
- [x] 1.4 Implement `FinancialStatementCalculator.call` (Q1–Q6, figure rules, P&L close into capital, four checks, unmapped, warnings) per [design card ③](design.md#③-calculator) and [lld Queries](lld.md#queries-and-indexes), aggregate-only, working for `base: AccountEntry` and `AccountEntrySqlite`. Verify: `rails runner` on a dev fund returns lines without loading `AccountEntry` rows (check the log for grouped SELECTs only).
- [x] 1.5 Add a read-only Mapping tab skeleton (`FinancialStatementMappingsController#show`, policy, route, fund Actions link) that renders accounts with a Preview column and the Checks for a chosen period. Verify: the page opens for a dev fund.
- [x] 1.6 Write `features/fund/financial_statements/financial_statement_calculator.feature` covering H9, H10, E4, E5, E6, E7, E13, E14, E21, E24, E29, E30, X10 (data set up by factories, figures read from the preview/checks), plus `features/step_definitions/financial_statement_steps.rb` and factories. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statement_calculator.feature` and confirm green before starting phase 2.

## 2. Mapping, layout and settings screens

- [x] 2.1 Accounts, mapping rules, definitions and settings CRUD controllers + policies + Turbo Stream views per [lld Controllers](lld.md#controllers-params-and-responses); account and core-definition delete guards. Verify: add/edit/delete in the browser; deleting an in-use account shows the refusal.
- [x] 2.2 Unmapped panel with **Map** pre-fill and live Preview frame refresh on every rule save ([design card ①](design.md#①-mapping)). Verify: mapping Director Fees removes it from Unmapped without reload.
- [x] 2.3 Layout tab: rows per definition, headings/accounts/subtotals, ↑ / ↓ reorder (no drag library in the app), Add schedule. Verify: reorder persists after reload.
- [x] 2.4 Start `docs/user_guides/financial_statements_user_guide.md` (with mermaid diagram and FAQ per the user-guide standard) covering mapping, layout, schedules and settings. Verify: UserGuideLint passes.
- [x] 2.5 Write `features/fund/financial_statements/financial_statement_mapping.feature` covering H1, H2, H21, H22, H23, H3, H4, H5, H6, H7, H8, E2, E3, E17, E22, X5, X17, X6. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statement_mapping.feature` and confirm green before starting phase 3.

## 3. Statements run (engine) and generation

- [x] 3.1 Add `AccountEntryAllocation::GenerateFinancialStatementLines` and its `when` in `RunFormula` per [design card ④](design.md#④-statements-run): one evaluation per fund, `AccountEntrySqlite` rows with entry_type "Financial Statement", names "<account>" / "YTD <account>", `json_fields {fs_account_id, column}`. Verify: a tagged run on a dev fund writes the expected rows.
- [x] 3.2 Exclude `GenerateFinancialStatementLines` from `RunFormulas#formulas_in_scope` unless the tag list includes "Financial Statements"; add the always-true step `refresh_financial_statements` after `generate_soa` that enqueues `FinancialStatementRefreshJob`; update `run_formulas.md`. Verify: an untagged run on a dev fund leaves FS entries untouched.
- [x] 3.3 Add `FinancialStatement` model, `FinancialStatementGenerate` (guards in the card ⑤ order, `fund.with_lock`, new `AllocationRun` + `AccountEntryAllocationJob`) and `FinancialStatementRefreshJob` per [lld Method Contracts](lld.md#method-contracts) and [Transactions](lld.md#transactions-locking-and-concurrency). Verify: Generate on a dev fund produces a Draft with checks and unmapped count.
- [x] 3.4 `FinancialStatementsController#index/#create/#regenerate` and the Statements tab list with derived Generating/Failed/Ready states (Turbo Stream refresh). Verify: list updates from Generating to Draft without manual reload.
- [x] 3.5 Write `features/fund/financial_statements/financial_statement_generation.feature` covering H24, H12, H13, H14, E1, E12, E16, E25, E28, X1, X2, X3, X4, X11, X15, X16. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statement_generation.feature` and confirm green before starting phase 4.

## 4. Statement view, lock, comparatives, drift and exports

- [x] 4.1 Statement view with definition switcher, columns per column style, Checks panel, unmapped link; `FinancialStatement#lines_for` reading FS entries (draft) or `frozen_data` (locked). Verify: Q3 dev statement renders all definitions.
- [x] 4.2 `FinancialStatementLock` + `#lock` action: `lockable?` gate, `frozen_data` snapshot, audit columns, statements run locked. Verify: lock disabled with unmapped entries; lock succeeds otherwise.
- [x] 4.3 Comparatives (`comparative_for`) and drift banner (`drift`) per [design card ⑤](design.md#⑤-statement-record). Verify: editing a locked period's entry shows the banner.
- [x] 4.4 `FinancialStatementXlsx` (sheet per definition) and `FinancialStatementPdf` (FerrumPdf like the fund dashboard PDF, DRAFT watermark, locked → frozen figures); dates via `l(...)`. Verify: both downloads open and match the screen.
- [x] 4.5 Extend the user guide with generate/lock/comparatives/drift/downloads and their FAQs. Verify: UserGuideLint passes.
- [x] 4.6 Write `features/fund/financial_statements/financial_statements.feature` covering H15, H18, H19, H20, E9, E10, E11, E26, X8, X9, X13, X14. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statements.feature` and confirm green before starting phase 5.

## 5. Unlock guard and notification

- [x] 5.1 `FinancialStatementUnlockGuard` (`affected`, `demote!`) and calls from `AllocationRunsController#unlock`/`#unlock_all`, byte-identical when nothing is affected ([design card ⑦](design.md#⑦-unlock-guard)). Verify: unlock on a period without locked statements behaves as before.
- [x] 5.2 Action-summary popup in `funds/_allocation_runs.html.erb` (Bootstrap modal, three cards) when locked statements overlap, one preload per page. Verify: popup lists the right periods.
- [x] 5.3 `FinancialStatementNotifier < BaseNotifier` + mailer + view; recipients via `EvergreenRecipients#tagged("FundAccounting")`; one delivery per unlock request; email dates via bare `l(date)`. Verify: one email + in-app alert per unlock in dev (letter_opener).
- [x] 5.4 Extend the user guide with the unlock warning and notification FAQs. Verify: UserGuideLint passes.
- [x] 5.5 Write `features/fund/financial_statements/financial_statement_unlock_guard.feature` covering H16, H17, E8, E15, E23. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statement_unlock_guard.feature` and confirm green before starting phase 6.

## 6. AI-drafted mapping

- [x] 6.1 `FinancialStatementMappingSuggestion` model (`approve!`, `discard!`) and upload controller with type/size validation per [lld Controllers](lld.md#controllers-params-and-responses). Verify: .docx refused, PDF accepted.
- [x] 6.2 `FinancialStatementMappingPrompt` (prompt, JSON schema, parser) and `FinancialStatementMappingSuggestJob` using `DocLlmContext`/`LlmService`, reconciling each line through the calculator; failure → `failed` + toast ([design card ②](design.md#②-ai-draft)). Verify: on a dev fund with a real statement PDF the draft shows ✓/⚠ lines.
- [x] 6.3 Draft review page (printed / CapHive / match, added/changed vs existing mapping, Approve / Discard / Retry). Verify: approve creates accounts, layout and rules without duplicates.
- [x] 6.4 Extend the user guide with "Suggest from statements" and its FAQs. Verify: UserGuideLint passes.
- [x] 6.5 Write `features/fund/financial_statements/financial_statement_ai_draft.feature` covering H11, E18, E19, E20, E27, X7, X12, X18 with `LlmService` stubbed to fixture JSON. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/financial_statements/financial_statement_ai_draft.feature` and confirm green before starting phase 7.

## 7. Wrap-up

- [x] 7.1 Run `bundle exec rubocop` on all changed files (including `IRM/RelationBlankPresent`) and fix offences. Verify: no offences.
- [x] 7.2 Re-run all six feature files together plus the existing allocation-run features that touch unlock and `formulas_in_scope` (`TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/financial_statements features/<existing allocation run features>`). Verify: green.
- [ ] 7.3 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off.
