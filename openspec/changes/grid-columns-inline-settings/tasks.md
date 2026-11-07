# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — screenshot each new/changed screen next to the reference screen named in design.md's
> *Screen standards* and apply the UI self-review checklist; (b) **N+1 check** — run the phase's features under
> Prosopite and fix every N+1 in this change's code; (c) run the phase's Cucumber features green. Do not start the
> next phase until all three pass.
>
> Worked-example IDs come from [business-rules.md](business-rules.md). Every scenario carries a `# ID — …` comment;
> code comments name the IDs of the paths they implement. Redis must be up on 6379; every run uses a fresh
> `TEST_ENV_NUMBER=$RANDOM`; wait on each run's PID, never a pgrep loop; no code edits while a run is going.

## 1. Table columns panel (Ransack tables)

- [x] 1.1 Extract `GridColumnOptions` from `GridViewPreferencesController#configure_grids` (LLD › Method Contracts,
      design D7); `configure_grids` flattens it. Verify: `features/core/custom_grid_view.feature` green and the
      Configure Grids dropdown lists the same options on dev entity 157 (Investor, CapitalCommitment).
- [x] 1.2 Add `GridColumnsContext` (sign/verify, `form_type_for`, `owner`) and `RansackTableHeader#grid_columns_context`,
      `#grid_columns_allowed?`; switch the header's form-type lookup to `form_type_for`; version the cache key by
      the report record; `GridViewPreference#touch_entity` also touches a Report owner (LLD › Method Contracts,
      design D2, D6, D10). Verify: a runner round-trips a token and rejects an altered one; existing table pages
      render on dev (render check of Investors, Capital Commitments, Capital Calls).
- [x] 1.3 Add `GridViewPreferencePolicy#inline_columns?` (LLD › Security Detail, design D11). Verify: policy returns
      true for a company admin, false for an employee, an investor-role user and another firm's report.
- [x] 1.4 Add `GridColumnsSave` (LLD › Method Contracts steps 1–7, Transactions; design D4, D5) with ID comments
      (E5, E6, E7, E8, H6, X4, X6). Verify: a runner save on a test owner gives positions 1..n and refuses `entity.users`.
- [x] 1.5 Add `GridColumnsController` (`settings`, `save`), routes, `grid_columns/settings.html.erb`, `_saved.html.erb`,
      `_button.html.erb` (LLD › Controllers, Params and Responses). Verify: `bin/rails routes | grep grid_columns`;
      GET settings with a fresh token renders the panel body on dev.
- [x] 1.6 Extract `app/javascript/custom/side_panel.js` (`ensurePanel`, `showToast`, `prefersReducedMotion`,
      `bindEscape`, `refreshPage`) from `widget_settings_controller.js` and use it there (design D12). Verify:
      `features/core/dashboard_widget_inline_settings.feature` and `..._refresh.feature` green.
- [x] 1.7 Add `grid_columns_controller.js`, `grid_columns_form_controller.js` and `custom/grid_columns.scss`;
      wrap `ransack_table.html.erb` in the host with `_button` (design D1, D8, D9). Verify: on dev, hover shows ▥,
      the panel opens, edits stay client-side, Save reloads only the table frame.
- [x] 1.7a Make ▥ always visible and move it next to the search box (design D18). Verify: on dev Investors the
      button sits right of the search input; with `hide_search=true` it shows at the table's top-right.
- [x] 1.7b Add data type, alignment, derived key and "Add derived field" to the panel and `GridColumnsSave`
      (design D20, LLD step 5b) with ID comments (H18, E23, E24, X19). Verify: runner save sets Decimal/text-end
      and creates a derived row; `Ruby` is refused.
- [x] 1.7c Configure Grids on the shared list (design D19): extract `grid_columns/_editor`, `GridColumnsContext.for_owner`
      (+ explicit form type id), `configure_grids` renders the editor embedded with per-row Show / Edit / Delete,
      remove `new`/`create` + `new.html.erb`, keep `show edit update destroy update_column_sequence`; update
      `features/core/custom_grid_view.feature`, M15/L14 security steps and drift-guard allowlists. Verify: Configure
      Grids renders on dev for Investor and a report; report builder Columns tab drag still saves.
- [x] 1.8 Write `features/core/grid_columns_inline_settings.feature` (H1–H8, H16–H18, E1–E11, E23–E27, X6) and
      `features/security/grid_columns_inline_settings_isolation.feature` (X1–X5, X7–X9, X19, X20) with step file
      `features/step_definitions/grid_columns_inline_settings_steps.rb`; header links business-rules.md §1.
- [x] 1.9 UI review: screenshots (dev DB via Warden runner) of the Investors table with ▥ and the open columns
      panel beside the widget settings panel (`dashboard_widgets/settings.html.erb`); fix differences.
- [x] 1.10 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/grid_columns_inline_settings.feature features/security/grid_columns_inline_settings_isolation.feature`;
      truncate `log/prosopite.log` first, read it, fix every N+1 in this change's code.
- [x] 1.11 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/grid_columns_inline_settings.feature features/security/grid_columns_inline_settings_isolation.feature features/core/custom_grid_view.feature features/core/dashboard_widget_inline_settings.feature features/core/dashboard_widget_inline_settings_refresh.feature features/security/security_surface_drift_guard.feature features/security/security_review_2026_10_low.feature features/security/security_review_2026_10_medium.feature`
      plus the report builder columns features, and confirm green before starting phase 2.

## 2. Hand-built list tables

- [x] 2.1 Make `grid_columns_controller` place ▥ beside `.dataTables_filter` once DataTables draws, and have the
      Form Type page offer Configure Grids whenever `configure_grids?` (design D21). Verify: on dev the Funds list
      shows ▥ right of "Search:"; Form Types › Capital Distribution shows Configure Grids.
- [x] 2.2 Convert the lists whose model already has standard columns — Funds, Investments, Investment
      Instruments, Deal Investors: `STANDARD_COLUMNS` = today's columns, decorator methods for rich cells, view →
      `RansackTable(sortable: false)`, row partial → `RansackTableRow` + Actions (design D21). Verify: dev
      screenshots before/after match; ▥ opens the panel.
- [x] 2.3 Convert the 10 lists (Deals dropped: dead partial) that need standard columns first — Distributions, Allocations, Approvals,
      Approval Responses, Expressions of Interest, Investment Opportunities, Investor KPI Mappings,
      Portfolio Cashflows, Secondary Sales, Users — the same way. Verify: dev screenshots before/after match.
- [x] 2.4 Write `features/core/grid_columns_hand_built_lists.feature` (H19, H20, E28–E30); header links
      business-rules.md §1b; run the existing features of each converted list alongside it.
- [x] 2.5 UI review: before/after screenshots of all 14 lists; fix differences.
- [x] 2.6 N+1 check under Prosopite for the lists feature and each list's own features; fix every N+1 in this
      change's code.
- [x] 2.7 Run the phase's features green before starting phase 3.

## 3. AG grid columns

- [x] 3.1 Render the host and `grid_columns/_button` in the 4 AG grid partials (capital commitments, account
      entries, interests, portfolio investments) from their `ransack_table_header` (LLD › File Map, design D1).
      Verify: on dev the ▥ icon shows on the Capital Commitments grid and Save reloads only the grid.
- [x] 3.2 Add H9 and E12 to `features/core/grid_columns_inline_settings.feature` (business-rules.md §2).
- [x] 3.3 UI review: Capital Commitments grid with ▥ and panel beside the phase 1 screenshot; fix differences.
- [x] 3.4 N+1 check under Prosopite for the grid scenarios; fix every N+1 in this change's code.
- [x] 3.5 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/grid_columns_inline_settings.feature`
      and confirm green before starting phase 4.

## 4. Custom fields panel on record pages

- [x] 4.1 Move the calculation guard from `FormTypesController#update` into `FormType#calculation_change_allowed?`
      and call it there (LLD › Phase 3 contracts, design D14). Verify: `features/core/custom_fields.feature` and
      `features/misc/regulatory_custom_fields.feature` green.
- [x] 4.2 Add `FormTypePolicy#inline_fields?` (design D17). Verify: true for a company admin, false for an employee,
      an investor-role user and another firm's form type.
- [x] 4.3 Add `FormTypeFieldsSave` (LLD › Phase 3 steps 1–7, design D14, D15) with ID comments (H13, E13, E16, E18,
      E20, X13–X16). Verify: a runner save reorders without moving regulatory fields and refuses a duplicate name.
- [x] 4.4 Add `FormTypeFieldsController` (`settings`, `save`), routes, `form_type_fields/settings.html.erb`,
      `_saved.html.erb`, `_anchor.html.erb`; `display_custom_fields` renders the anchor when `custom_fields:` is
      empty and `inline_fields?` (design D13). Verify: Investor and Capital Commitment show pages render on dev;
      the reporting fields list renders no anchor.
- [x] 4.5 Add `form_type_fields_controller.js` (icon on the card, open, saved → `refreshPage`) and
      `form_type_fields_form_controller.js` (drag, rename, flags, help, remove/undo, add); field-row styles in
      `grid_columns.scss` (design D16). Verify: on dev the 🗎 icon shows on Ravi-Menon-like investor pages; Save
      refreshes in place with scroll kept.
- [x] 4.6 Write `features/core/custom_fields_inline_settings.feature` (H10–H15, E13–E22, X13–X15) and
      `features/security/custom_fields_inline_settings_isolation.feature` (X10–X12, X16–X18) with
      `features/step_definitions/custom_fields_inline_settings_steps.rb`; header links business-rules.md §3.
- [x] 4.7 UI review: Investor and Capital Commitment show pages with 🗎 and the open fields panel beside the widget
      settings panel and the approved mock; fix differences.
- [x] 4.8 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/custom_fields_inline_settings.feature features/security/custom_fields_inline_settings_isolation.feature`;
      fix every N+1 in this change's code.
- [x] 4.9 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/custom_fields_inline_settings.feature features/security/custom_fields_inline_settings_isolation.feature features/core/custom_fields.feature features/misc/regulatory_custom_fields.feature features/security/security_surface_drift_guard.feature`
      and confirm green before starting phase 5.

## 5. Coverage, docs and hand-off

- [x] 5.1 Coverage: list every H/E/X ID in business-rules.md and every `# ID —` comment in the 4 feature files;
      confirm the sets are equal (71 IDs); any new edge case gets a business-rules row and a scenario.
- [x] 5.2 Update `docs/user_guides/custom_fields_user_guide.md` (fields panel, columns panel; FAQ "How do I change
      which columns show in a record list?" and a new "Can I change a record's custom fields from its page?"),
      following the user-guide FAQ standard; run UserGuideLint. Verify: lint passes.
- [x] 5.3 Brakeman on the changed files (0 new warnings) and rubocop on changed Ruby files (clean).
- [x] 5.4 Fill design.md and lld.md "Changed during the build" with anything the build changed.
- [ ] 5.5 Run the regression set: all features from 1.11, 2.5 and 3.9 together, green.
- [ ] 5.6 (QA, not the apply agent) Run qa-checklist.md on a deployed build and record the sign-off.

## Apply log

| # | Date | What happened |
|---|---|---|
| 1 | 2026-11-07 | Phase 1 green: 38 new scenarios + custom_grid_view (14, steps retargeted to the shared editor), widget settings, security review low/medium, drift guard. First run: 9 failures, all in new steps (sort arrows in headings, Playwright drag API, rack_test GET query). |
| 2 | 2026-11-07 | Prosopite: no N+1 in this change's code. Shared-code N+1 listed, not edited: `investor_kycs/_stats.html.erb:19` (count per status in a loop). |
| 8 | 2026-11-07 | Phase 5: coverage 71 IDs = 71 scenario comments; rubocop clean on this change's lines (5 pre-existing offenses in committed lines left); Brakeman: no new warnings (the one in form_types_controller.rb:176 is a pre-existing `constantize` in an untouched action); user guide updated (two sections, two diagrams, three FAQs, lint clean). |
| 7 | 2026-11-07 | Phase 4: fields panel on record pages and (user) at the form level; icon beside the card's minimize button / in the form card header / breadcrumb bar. 55 scenarios green (26 new + custom_fields + regulatory_custom_fields); first run 2 failures in new scenarios (H11 asked for Read only on a required field — a model rule; E16 setup positions). Fixed alongside: nested-field error messages shown without their "Form custom fields …" prefix; locked rows kept when the panel re-renders after a refused save. Prosopite: no N+1 in this change's code. |
| 5 | 2026-11-07 | Phase 2 gate: lists feature (5) + 27 features of the converted lists — 238/243 first run; 4 real failures (EOI approve/update re-rendered the row without `columns` → `ExpressionOfInterestsController#eoi_row_stream`), 1 timing flake (capital_distributions:272, green serially). Rerun green. |
| 6 | 2026-11-07 | Phase 3: the 4 AG grids wrapped (icon on the grid's corner; Account Entries / Interests wrap the grid only so the icon clears the header buttons). H9, E12 green. Prosopite over phases 2–3 (113 scenarios): no N+1 in this change's code; shared-code ones listed, not edited: capital_distributions/_journey.html.erb:11 (Investor#notification_users), expression_of_interests/_stats.html.erb:19, EoiAction#save, investors/_investor row policy (InvestorPolicy#edit?). |
| 4 | 2026-11-07 | Phase 2 conversions: Funds, Distributions by me; the other 12 by three parallel forks with before/after heading and first-row captures (identical except the Actions heading label; paged Investments gains a "Displaying items" line). Deals skipped (dead partial). |
| 3 | 2026-11-07 | Bug found while writing E2: a required column already in the resolved set was locked and dropped on save; now only page-added columns are locked (`RansackTableHeader#grid_columns_added_keys`). |
