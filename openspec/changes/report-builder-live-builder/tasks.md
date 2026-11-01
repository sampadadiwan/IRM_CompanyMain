# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Traceability:** every scenario has a `# <ID> — <Happy path|Edge case|Error case>: …` comment, each feature header links to `openspec/changes/report-builder-live-builder/business-rules.md`, and code comments name the IDs they implement. Redis must be up on 6379.

## 1. Page shell, update responder and look (① ⑥)

- [x] 1.1 Split `edit.html.erb` into the shell, `_builder_header` and `_settings_panel` with one partial per tab, moving content without changing behaviour ([LLD File Map ①](lld.md#file-map)); verify the existing `features/core/report_builder/` run is still green
- [x] 1.2 Add `ReportBuilder::BuilderUpdates#respond_with_builder_update` and make every mutating builder action use it for Turbo Stream requests, keeping HTML redirects and JSON as today ([LLD Controllers](lld.md#controllers-params-and-responses)); switch the builder's forms and `_save` to request streams; verify a stream request to `update_aggregate` returns the three targets
- [x] 1.3 Preview frame loads by itself (`src`, builder mode); remove the Build/View toggle and `switchMode`; header gets Guide, ⌘K button, Health frame and Open report; preview errors render inside the frame; empty-state copy names the next action
- [x] 1.4 Apply the app's styling in the builder (no `table-dark`, no uppercase `fs-1` labels, no inline widths; standard badges and outline buttons) and add `title` + `aria-label` to every icon-only button; verify against the UI self-review checklist with a screenshot
- [x] 1.5 Write `features/core/report_builder/editor_page.feature` (H17, E19, E20) with `report_builder_editor_steps.rb` (stream request and target steps). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_page.feature features/core/report_builder/`
      and confirm it passes before starting phase 2.

## 2. Column picker, bulk add and header menus (② ③)

- [x] 2.1 `ReportBuilderColumnCatalog.grouped_for` (kinds, `_id`/`_cents` hidden, same-label hints) and `_column_groups`; Add selected with `keys[]` (server-side labels, skip existing, refuse disallowed, auto-join curated relations) ([design ②](design.md#-column-picker)); verify H4 by request
- [x] 2.2 Builder-mode `_preview_table` header menus (`_column_menu`: Rename, Total, Move, Remove; formula and pivot variants) and `move_column` + route ([design ③](design.md#-header-menu)); verify moving a column in the browser
- [x] 2.3 Write `features/core/report_builder/editor_columns.feature` (H2, H3, H4, H6, E1, E2, E3, E4, E5, E6, X3). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_columns.feature`
      and confirm it passes before starting phase 3.

## 3. Typed filters that save themselves (④)

- [x] 3.1 `ReportBuilderFilterField` (kinds, operators, options with `distinct.limit(31)` outside `LARGE_TABLES`, validation) ([LLD Method Contracts](lld.md#method-contracts)); verify kinds for Investor category, commitments fund, remittances status in `bin/rails runner` (test env)
- [x] 3.2 `_filter_row` with the right input per kind (`date_field_tag` for dates), JS `filterChanged` (600 ms debounce, row validation, stream save) and removal of Save All Filters; verify in the browser
- [x] 3.3 Write `features/core/report_builder/editor_filters.feature` (H8, E7, E8). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_filters.feature`
      and confirm it passes before starting phase 4.

## 4. Formula editor and pivot preview (⑤)

- [x] 4.1 `_formula_modal` with column buttons inserting at the cursor and the sample table; `validate_formula` returns `samples` for the first 5 rows ([design ⑤](design.md#-formula-editor)); verify H10 by request
- [x] 4.2 `ReportBuilderPivotAggregator#preview_columns` and `GET :id/pivot_preview`; pivot form shows "This will create N columns: …" and warns above 20; verify by request
- [x] 4.3 Write `features/core/report_builder/editor_formulas.feature` (H10, E11) and `features/core/report_builder/editor_pivot.feature` (H16, X2). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_formulas.feature features/core/report_builder/editor_pivot.feature`
      and confirm it passes before starting phase 5.

## 5. Undo (⑥)

- [x] 5.1 `ReportBuilderUndo` (snapshot with `after_digest`, restore with lock, drop on other changes), `undo` action + route, Undo toast, `remove_join_summary` popup listing columns ([LLD Transactions](lld.md#transactions-locking-and-concurrency)); verify H11 by request
- [x] 5.2 Write `features/core/report_builder/editor_undo.feature` (H11, H12, H13, E12, E13, X1). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_undo.feature`
      and confirm it passes before starting phase 6.

## 6. Health check (⑦)

- [x] 6.1 `ReportBuilderHealthCheck` (blank columns, formula refs, mixed currencies, empty filters, large pivot, large export, default totals) and `_health` badge + panel with Fix links to tabs ([design ⑦](design.md#-health-check)); verify H15 in `bin/rails runner` (test env)
- [x] 6.2 Write `features/core/report_builder/editor_health.feature` (H14, H15, E14, E15, E16, E17, E18). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_health.feature`
      and confirm it passes before starting phase 7.

## 7. Browser behaviour of the builder (① ③ ④ ⑤)

- [x] 7.1 Write `features/core/report_builder/editor_live.feature` (`@javascript`: H1, H5, H7, H9, E9, E10) with browser steps. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/editor_live.feature`
      and confirm it passes before starting phase 8.

## 8. Guided wizard (⑧)

- [x] 8.1 Step 1 cards (examples for every root, no name), `wizard_create` error for unknown tables; steps `show`, `fund_filters`, `order`, `check` with old-name redirects ([design ⑧](design.md#-guided-wizard)); verify each step renders
- [x] 8.2 Step 2 with `_column_groups` (root + curated related columns, inline totals); live sample frame on steps 2–5; step 3 fund picker (`wizard_fund`) and sentence filters with `_filter_row`
- [x] 8.3 `ReportBuilderSuggestions` (Called %, Unpaid, Uncalled, DPI; suggested name); step 4 suggestions; step 5 `_summary_cards`, `_health`, preview, name, `wizard_save`, Fine-tune
- [x] 8.4 Remove `report_builder_wizard.scss` and the replaced wizard views; step bar with Bootstrap utilities; grep that nothing references the removed files
- [x] 8.5 Rewrite `features/core/report_builder/wizard.feature` (H18–H30, E21–E26, X4, X5) and `report_builder_wizard_steps.rb`. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/wizard.feature`
      and confirm it passes before starting phase 9.

## 9. Docs and wrap-up

- [x] 9.1 Update `docs/user_guides/report_builder_user_guide.md` (layout, header menus, filters, undo, health, wizard) with FAQs per the user-guide standard; run `features/core/user_guide_lint.feature` green
- [x] 9.2 Coverage check: every H/E/X ID in `business-rules.md` has exactly one `# <ID> —` scenario under `features/core/report_builder/`, and none without an ID
- [x] 9.3 `bundle exec rubocop` on every touched Ruby file is clean; screenshots of the builder, a header menu, filters, health panel and each wizard step reviewed against the UI self-review checklist
- [x] 9.4 Run the whole folder `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/` and confirm it passes.
- [ ] 9.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off.
