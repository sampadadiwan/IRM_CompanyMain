# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Traceability:** every scenario has a `# <ID> — <Happy path|Edge case|Error case>: …` comment above it,
> each feature header links to `openspec/changes/report-builder-trust/design.md#worked-examples`, and code
> comments name the IDs of the paths they implement. Redis must be up on 6379 for every run.

## 1. Column catalog, column type and default totals (② ③ ①)

- [x] 1.1 Add `ReportBuilderColumnType` (`AGGREGATES`, `type_for`, `default_aggregate`, `strategy_for`, `totalable?`, `aggregate_label`) per [LLD Method Contracts](lld.md#method-contracts); verify in `bin/rails runner` that `strategy_for("capital_commitments")` on Investor is `:grouped`, `"capital_commitments.fund"` is `:anchored_many`, and `"fund"` on CapitalCommitment is `:anchored_one`
- [x] 1.2 Add `ReportBuilderColumnCatalog` (`columns_for`, `filter_only_for`, `related_columns_for`, `preloads_for`, `filter_columns_for`, `read(record, key)` with plain-text `READERS` for decorator-only columns) and make `ReportBuilderController#columns_for_model` / `column_key_allowed?` delegate to it ([LLD File Map ②](lld.md#file-map)); verify the Capital Distribution column list no longer contains "Carry" and its filter list does
- [x] 1.3 Make the engine's root-column read use `ReportBuilderColumnCatalog.read` and apply `preloads_for` to the root scope ([design ④](design.md#-query-engine)); verify a remittance report shows Investing Entity in the preview
- [x] 1.4 Add `ReportBuilderConfig#effective_aggregate` and use it wherever the engine and exporter read aggregates; `add_column` stores the default for many-per-row keys; `update_aggregate` refuses totals outside `AGGREGATES` with 422 / alert ([LLD Controllers](lld.md#controllers-params-and-responses)); verify via the HTTP steps that adding Committed stores `sum`
- [x] 1.5 Wizard Summarize (`wizard/aggregates.html.erb`) selects `effective_aggregate` and uses `aggregate_label`; `wizard_type_icon_for` wraps `type_for`; verify by adding Committed in the wizard and reloading
- [x] 1.6 Write `features/core/report_builder/column_catalog.feature` (H6, E12, E13, E14) and extend `aggregation.feature` (H7, E2, E3, X2) and `wizard.feature` (H25, H26), adding the shared `Given the Acme report builder data` step ([LLD Test Plumbing](lld.md#test-plumbing)). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/column_catalog.feature features/core/report_builder/aggregation.feature features/core/report_builder/wizard.feature`
      and confirm it passes before starting phase 2.

## 2. Related data: anchored joins, two-step, polymorphic, pivot labels, only-with-rows (④ ①)

- [x] 2.1 `ReportBuilderChildAggregator`: anchored mode (`base_class` root, `fk` `id`, nested `joins`, internal `value` = MAX) and the `bare_col` fix for grouped deep keys; polymorphic `reflection.type` condition in grouped mode ([LLD Queries](lld.md#queries-and-indexes)); verify H1/H3 values in `bin/rails runner` against the dev DB (read-only)
- [x] 2.2 `ReportBuilderQueryEngine#pass2` chooses the strategy via `strategy_for`; `merge` looks up the longest configured relation prefix; unresolvable paths log a warning with the report id and yield blanks ([LLD Error Mapping](lld.md#error-mapping-and-logging)); verify an Investor report with both `capital_commitments` and `capital_commitments.fund` fills both
- [x] 2.3 `ReportBuilderPivotAggregator`: header label `"<relation label> · <value> (<agg>)"` and the polymorphic condition; verify two pivots on one report have distinct headers
- [x] 2.4 `root_scope` with `only_with_rows` (`IN (child scope).select(fk)`), shared by `run` and `count`; new `update_join_settings` action + route (refuses anchored joins and unknown relations); switch on grouped join cards in `edit.html.erb` wired to `toggleOnlyWithRows` ([design ①](design.md#-report-set-up)); verify the row count drops from 4 to 3 on Report "LPs"
- [x] 2.5 Write `features/core/report_builder/related_data.feature` (H1, H2, H3, H4, H5, H12, E1, X1) and `features/core/report_builder/only_rows.feature` (H13, H14, E11, X8, X9), and add E28 to `aggregation.feature`. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/related_data.feature features/core/report_builder/only_rows.feature features/core/report_builder/aggregation.feature`
      and confirm it passes before starting phase 3.

## 3. Formulas on plain numbers and column order (⑤ ①)

- [x] 3.1 `ReportBuilderFormulaService#evaluate` converts `Money` to `BigDecimal` before Dentaku ([design ⑤](design.md#-formulas)); verify `ROUND([committed_amount] / [call_amount], 2)` gives `2.5` for C1-like data in `bin/rails runner`
- [x] 3.2 Placeholder rows: `add_formula` creates `formula:<key>`, `remove_formula` deletes it; `update_pivot` creates/deletes `pivot:<relation>`; `remove_join` deletes the pivot placeholder; all in one transaction ([LLD Transactions](lld.md#transactions-locking-and-concurrency)); verify rows appear and disappear in `grid_view_preferences`
- [x] 3.3 `ReportBuilderQueryEngine#columns` expands placeholders in sequence order and appends unplaced pivots then formulas (today's order); update every GVP consumer listed in the [File Map](lld.md#file-map) (sort/grouping dropdowns, `default_search_predicate`); verify dragging Called % after Called changes preview order
- [x] 3.4 Write/extend `features/core/report_builder/formulas.feature` (H8, H9, E6, X7) and `features/core/report_builder/column_order.feature` (H10, H11, E7, E8, E9, E10). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/formulas.feature features/core/report_builder/column_order.feature`
      and confirm it passes before starting phase 4.

## 4. Formatter, totals, report page and Excel (⑥ ⑦)

- [x] 4.1 Add `ReportBuilderValueFormatter` (`display`, `align`, `xlsx`) and `ReportBuilderTotals` (`call`, `label`) per [LLD Method Contracts](lld.md#method-contracts); verify in `bin/rails runner` that the totals for Report "LPs"-like rows give Committed 8,50,00,000 and Called % 40.0
- [x] 4.2 `_preview_table.html.erb` and `ReportBuilderController#preview`: `PREVIEW_LIMIT = 20`, formatter cells, totals row with `:all`/`:sample` label, "N of M rows" / "All N rows"; fix the "50 rows" copy in `edit.html.erb`; verify in the browser on the dev server
- [x] 4.3 `ReportBuilderTable` + `view.html.erb` + `ReportBuilderController#view`: formatter cells, right-aligned numbers, header sort links keeping `q`/`page`, `sort_override` passed to the engine (validated against output columns), `<tfoot>` totals with `:all`/`:page`, capped-sort note ([design ⑦](design.md#-screens-and-excel)); verify by clicking headers on the dev server
- [x] 4.4 `ReportBuilderXlsxExporter`: values and number/date formats via the formatter, bold totals as the last Data-sheet row, remove `add_totals_sheet`; update the existing Totals-sheet expectation in `xlsx_exporter.feature`; verify by opening an exported file
- [x] 4.5 `reports/_card.html.erb`: builder report name → `view_report_builder_path`; Edit unchanged; verify on the Reports list
- [x] 4.6 Write `features/core/report_builder/display_formatting.feature` (H15, H24, E15, E16, E20, X6), `features/core/report_builder/totals.feature` (H17, H18, E17, E18, E19, E30, E31), `features/core/report_builder/view_sort.feature` (H20, H21, E21, E22, E23, E24, X4, X5), extend `xlsx_exporter.feature` (H16, H19) and add E4, E5 (Yes/No display) to `aggregation.feature`. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/display_formatting.feature features/core/report_builder/totals.feature features/core/report_builder/view_sort.feature features/core/report_builder/xlsx_exporter.feature features/core/report_builder/aggregation.feature`
      and confirm it passes before starting phase 5.

## 5. Builder feedback, template confirmation, docs and wrap-up (⑦)

- [x] 5.1 `report_builder_controller.js`: `_patch` rejects on non-2xx with the server message; every caller shows a red toast "{setting} wasn't saved — {reason}" and restores `data-saved-value`; green toast only on success ([LLD Error Mapping](lld.md#error-mapping-and-logging)); verify by forcing a 422 in the browser
- [x] 5.2 Add `ReportBuilderHelper#apply_template_summary` (action-summary cards: replaces columns, replaces related data and formulas, can't be undone) and switch Apply Template to `confirm#popup` with `data-msg`; grep `action_summary_modal.scss` for every modifier used; verify the popup on the dev server
- [x] 5.3 Update `docs/user_guides/report_builder_user_guide.md` (totals, header sort, only-with-rows, default totals, formulas on amounts, Excel totals row) with FAQs per the user-guide standard and run `UserGuideLint`; verify the lint passes
- [x] 5.4 Add the rollback note to the PR description: on revert, delete `grid_view_preferences` rows with keys starting `formula:` or `pivot:` ([LLD Configuration and Rollout](lld.md#configuration-and-rollout)); verify the note is in the PR body draft
- [x] 5.5 Coverage check: list every H/E/X ID in `design.md` and every `# <ID> —` comment under `features/core/report_builder/`, and confirm the sets are equal (no ID without a scenario, no scenario without an ID); confirm code comments name the IDs for each branch in [File Map](lld.md#file-map) files
- [x] 5.6 `bundle exec rubocop` on every touched Ruby file (including `IRM/RelationBlankPresent`) is clean
- [x] 5.7 Write `features/core/report_builder/builder_ui.feature` (`@javascript`: H22, H23, E25, E26, X3). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/builder_ui.feature`
      until green, then run the whole folder
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/`
      and confirm it passes.
- [ ] 5.8 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off.
