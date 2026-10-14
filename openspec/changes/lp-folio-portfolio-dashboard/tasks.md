# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens. If it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Traceability (required):** every H/E/X row in [business-rules.md](business-rules.md) gets exactly
> one Cucumber scenario, with a comment line directly above it, e.g.
> `# E12 — Edge case: a sub-unit allocation does not make a holding visible`. Each feature file header
> links to `openspec/changes/lp-folio-portfolio-dashboard/business-rules.md`. Code carries the same
> IDs on every service, policy and significant branch (guard, refusal, skip, fallback, rounding),
> e.g. `# E85 empty matching layout skipped; E54 none → holdings card only`. See
> [lld.md › Traceability Comments](lld.md#traceability-comments). Comment the steps inside method
> bodies, not just a header.

> **UX:** every new UI element follows [lld.md › UX Reuse Map](lld.md#ux-reuse-map): existing button
> bar, Misc dropdown, Bootstrap modals and action-summary confirm card, `alert-info`/`alert-warning`
> notices, `badge bg-*-subtle` badges, tooltips, the existing dashboard frame. No new CSS or colours.
> Every guidance notice links to the place where the fix happens.

> **Test runs:** `TEST_ENV_NUMBER=$RANDOM`, Redis up on 6379, launched in the background. Check for
> another running pcuc first. pcuc uses `-n 4`.

## 1. Fund LP portfolio view (box ①)

- [x] 1.1 Add migration `add_lp_portfolio_picks_to_funds` (two FK columns with indexes, `on_delete: :nullify`), and hand-edit `db/schema.rb` and `db/schema_test.rb` (LLD › Schema Detail). Verify: `bin/rails runner 'p Fund.column_names.grep(/lp_/)'` lists both on the test DB.
- [x] 1.2 Append `lp_folio_portfolio`, `lp_own_share` to the `flag :features` list in `FundEnabled`, after `use_own_fx_rates`. Diff the list against main first (fund-market-data risk) (LLD › Configuration and Rollout). Verify: `Fund.features.maps` shows bits 11 and 12.
- [x] 1.3 Create `LpPortfolioView` (`from_flags`, `apply`, `validate`, `OWN_SHARE_RULE_TYPES`), with step comments and IDs E3, X1–X5 (LLD › Method Contracts). Add `Fund#lp_portfolio_view(=)`, `#lp_own_share_ready?`, `#lp_folio_allocation_warning?` and the two `belongs_to`. Verify: a runner script sets each option and round-trips it.
- [x] 1.4 Replace the "Show fund portfolios to LPs" checkbox in `funds/_features.html.erb` with the LP portfolio view dropdown and the two formula pickers, revealed with the existing `conditional-visibility` controller. Add the ⓘ tooltip (E79). Permit the params in `FundsController` and flash the E1 warning (LLD › Controllers). Verify: the form renders in the browser for a fund with and without formulas.
- [x] 1.5 Confirm `ImportFund`'s "Show Portfolios" column still maps through `show_portfolios=` (E2, E3). Verify: import a one-row fund sheet in the console.
- [x] 1.6 Write `features/funds/lp_portfolio/lp_portfolio_view_setting.feature` covering **H4, H5, H6, H7, E1, E2, E3, E4, E7, E8, E79, X1, X2, X3, X4, X5**, one ID comment per scenario, with shared steps in `features/step_definitions/lp_portfolio_steps.rb`. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/lp_portfolio/lp_portfolio_view_setting.feature` until green before starting phase 2.

## 2. Visible set and LP portfolio screens (boxes ③ ④)

- [x] 2.1 Add `LpPortfolioVisibilityCache` (an `ActiveSupport::CurrentAttributes` with one `by_user` hash). `Current` stays limited to the acting user, as its header asks. Verify: it resets between requests (Rails clears all CurrentAttributes).
- [x] 2.2 Implement `LpFolioAllocationQuery.membership(pairs)` with the exact WHERE clause from LLD › Queries and Indexes, selecting only narrow columns, with ID comments (H2, E10–E21, E28a, E12/E13, E15, E17/E18, E20a). Verify: EXPLAIN on the production copy (port 33066, read only) shows the index intersection. Paste it into the PR description.
- [x] 2.3 Implement `LpPortfolioVisibility` (`for_user`, `for_investor`, `visible_api_ids`, `visible_pi_ids`, `visible_company_ids`, `qualifying_funds_for`, `folio_labels`), pairing each commitment with its own fund's allocation formula (feeders use the feeder's) (design card ③, LLD › Method Contracts). Verify: for Ravi on the seed data, `visible_api_ids(GF1)` returns Acme and Cedar only.
- [x] 2.4 Change the investor branch of `PortfolioInvestmentPolicy::Scope#resolve` / `#show?` and `AggregatePortfolioInvestmentPolicy::Scope#resolve` / `#show?` to the single OR condition. Comment it with H1, H2, E9, X17. Verify: employee scopes unchanged (existing portfolio features still pass, run in the background).
- [x] 2.5 In the LP holdings grid, add the "Showing investments allocated to your folio (…)" banner (`alert alert-info`) and the server-side totals row, and render the "No investments have been allocated to your folio yet." empty state (E24). Verify in the browser as Ravi.
- [x] 2.6 In `DashboardWidgetsHelper`, when the viewer is an investor and the fund's view is an *Allocated* option, keep only `LP_ALLOCATED_PORTFOLIO_WIDGETS` on the fund Portfolio Dashboard (E42). Verify: an LP sees only the holdings grid; *Whole fund* shows all charts.
- [x] 2.7 Write `features/funds/lp_portfolio/lp_folio_visibility.feature` covering **H1, H2, H15, E9, E10, E11, E12, E13, E14, E15, E16, E17, E18, E19, E20, E20a, E21, E22, E23, E24, E25, E26, E27, E28, E28a, E42, E43, X17**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/lp_portfolio/lp_folio_visibility.feature` until green before starting phase 3.

## 3. Own share (boxes ③ ④)

- [x] 3.1 Implement `LpFolioAllocationQuery.own_share` (the `ROW_NUMBER()` CTE, narrow columns) and `LpPortfolioVisibility#own_share(fund)` returning cost, fmv and `missing`, with comments E29–E33, E38, E39. Verify: for Ravi, Acme = 2.50 / 4.00.
- [x] 3.2 Add Your cost / Your FMV columns, the "—" with tooltip "Not yet allocated to your folio", the "Excludes N holdings not yet allocated." note, the formula/date info note and the LP-figure multiple to the LP grid, only when `lp_own_share_ready?` (E40, E41). Verify in the browser.
- [x] 3.3 Fund page notices for deleted picks: "Pick a new formula for Your FMV" and "Pick a new allocation formula" (E6, E6a). Verify by deleting a formula on a copy.
- [x] 3.4 Write `features/funds/lp_portfolio/lp_own_share.feature` covering **H3, E5, E6, E6a, E29, E30, E31, E32, E33, E34, E35, E36, E37, E38, E39, E40, E41**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/lp_portfolio/lp_own_share.feature` until green before starting phase 4.

## 4. Company sharing and LP layouts (box ⑤)

- [x] 4.1 Add migrations `widen_dashboard_widgets_name` (20 → 100) and `add_show_to_lps_to_investors`, and update both schema files (LLD › Schema Detail). Verify: `DashboardWidget.columns_hash["name"].limit == 100`.
- [x] 4.2 In `DashboardWidget`, add `LP_LAYOUT_TOKEN`, `LP_SAFE_WIDGET_NAMES`, `LP_ALLOCATED_PORTFOLIO_WIDGETS`, `lp_layout_name?`, `lp_layout_tags`, `lp_layouts_for`, the `lp_safe_in_lp_layout` validation (X6, E90) and the `name` length validation. Verify: saving a Notes widget into "LP, FinTech" fails with the X6 message.
- [x] 4.3 Implement `LpLayoutResolver.for(company)` → `Result(name, matched_tags, tie_with, fallback)`, with step comments E81, E82, E83, E84, E85, E54 (design card ⑤). Verify: console run on seed data gives "LP" for Acme and "LP, FinTech" for Paywise once that layout exists.
- [x] 4.4 Add `InvestorsController#lp_sharing` and `InvestorPolicy#lp_sharing?`. Add Show/Hide from LPs to the `investors/show` button bar with its tooltip (E72), the "Visible to LPs" badge, and the action-summary confirm modal for Hide (H18). Verify in the browser, including a double click (E45).
- [x] 4.5 Add `_lp_sharing_notice` on the company page: layout used (E91), tie warning (E92), no usable layout (E73), all funds hidden (E74). Each links onward. Verify each state in the browser.
- [x] 4.6 Add `DashboardWidgetsController#setup_lp_layout` and `#new_lp_layout` (transactional, idempotent, E52a, E88). Add the settings invite notice (E75), the LP layout notice with "used by N companies" (E76), selector labels and tooltip, the LP-safe type list and help texts on the form (E52, E77, E94). Verify in the browser.
- [x] 4.7 Add the `carry_over_show_portfolio_to_companies` data migration (single idempotent UPDATE, prints changed/skipped, `down` no-op), commented H17, E48–E51, X19. Verify on a local copy: second run reports 0 changed. Do not migrate the shared dev DB from this branch without asking.
- [x] 4.8 Write `features/funds/lp_portfolio/lp_company_sharing.feature` covering **H8, H8a, H9, H18, E45, E48, E49, E51, E52, E52a, E52b, E72, E73, E74, E75, E76, E77, E88, E89, E91, E92, E94, X6, X7, X8, X19**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/lp_portfolio/lp_company_sharing.feature` until green before starting phase 5.

## 5. LP Company Dashboard and its data paths (boxes ⑥ ⑦)

- [x] 5.1 Add `LpCompanyDashboardPolicy` (`show?`, `preview?`, `widget?`) following the access flowchart in design card ⑥, commented X9–X12, E53, X15. Verify: policy console checks for Ravi/Lena/Meera on seed data.
- [x] 5.2 Add routes and `LpCompanyDashboardsController#show` / `#preview` with the refusal and not-shared partials (`alert-warning` in a card) and `rescue_from Pundit::NotAuthorizedError` (LLD › Error Mapping). Verify: Bluefin as Ravi shows "You do not have access to this company."
- [x] 5.3 Build `lp_company_dashboards/show`: a way back to the fund portfolio (reuse the LP pages' breadcrumb pattern, or a back link), the holdings card (reusing `_card_table2`'s row layout), the fund selector in a turbo frame (H14, E59), and the widget area. Verify in the browser at desktop and phone width.
- [x] 5.4 Extend `dashboard_widgets(...)` with `lp_context:`. It uses the resolver's layout and the company's tags only (E86, E87), applies the LP-safe filter, never falls back to the catalogue (E54), and renders LP widget versions with the page (`lp_widget_partial`). In `_dashboard`, LP mode drops the Reports dropdown and layout selector (E54a). Verify: the internal Default dashboard renders exactly as before.
- [x] 5.5 Implement LP widget partials (via `lp_widget_partial`, rendered with the page — no separate widget address) and `LpWidgetData` loaders for KPIs (Actual only, E55, E56), KPI Performance Table, Valuations (instruments of visible holdings), Portfolio Stats (selected fund, E57), Portfolio Investments (existing endpoint with `fund_id`), Data Card, Key KPIs and Embed Document. Commented X13, X14. Verify each widget renders for Ravi.
- [x] 5.6 Add the `document.video?` branch to `documents/_embed` using `layouts/video` (H12, E64), and keep PDF/Excel unchanged (E61). Verify on an internal fund dashboard too.
- [x] 5.7 Add Preview as LP: a Misc dropdown item plus a modal to pick the LP and fund (reuse the workflow launch modal pattern), and the banner naming the layout (E93, E78, E65). Verify in the browser.
- [x] 5.8 Holding page: investor `show` redirects to the company dashboard (H16, E68, X16). Remove the Preview and Show/Hide Portfolio buttons, the attribute row, the `toggle_show_portfolio` action, route and policy method. Add the E80 notice. Remove the Widgets/Track Record tabs; records stay stored (E66, E67). In the LP grid, make company names links only when `openable?` (E44). Verify in the browser.
- [x] 5.9 Write `features/funds/lp_portfolio/lp_company_dashboard.feature` covering **H10, H11, H12, H13, H14, H16, H17, E44, E46, E47, E50, E53, E54, E54a, E55, E56, E57, E58, E59, E60, E61, E62, E63, E64, E65, E66, E67, E68, E78, E80, E81, E82, E83, E84, E85, E86, E87, E90, E93, X9, X10, X11, X12, X13, X14, X15, X16**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/funds/lp_portfolio/lp_company_dashboard.feature` until green before starting phase 6.

## 6. LP assistant scoping (box ⑦)

- [x] 6.1 In `RunQueryTool`, require `{VISIBLE_API_IDS}` when the SQL names `aggregate_portfolio_investments` and `{VISIBLE_PI_IDS}` when it names `portfolio_investments`, with integer-cast substitution, commented X18. Verify: a query without the placeholder returns the X18 message.
- [x] 6.2 In `LpChatProvider`, supply the ids from `LpPortfolioVisibility` (all ids for Whole-fund funds, visible ids for Allocated funds, none for Hidden funds). Update `skills/portfolio.md` to describe the placeholders and the company-level `show_to_lps`. Verify: the assistant answers H19 in a dev session.
- [x] 6.3 Write `features/ai/lp_assistant/lp_assistant_portfolio_scope.feature` covering **H19, E69, E70, E71, X18**, with a stubbed LLM using the existing assistant step pattern. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/lp_assistant/lp_assistant_portfolio_scope.feature` until green before starting phase 7.

## 7. Docs, coverage and review

- [x] 7.1 Update `docs/user_guides/portfolio_investments_user_guide.md` and the dashboard widgets user guide: LP portfolio view options, allocation formula, own share, company Show to LPs, LP layouts and tags, Preview as LP. Add a "Where to find it" box and why/how/what-happens FAQs, with a mermaid diagram. Verify: UserGuideLint passes.
- [x] 7.2 Run `features/ai/mcp_server/mcp_ontology.feature` once (LLD project rules: confirm no MCP surface changed or leaked through the narrowed scopes), and `bundle exec rubocop` on changed files including `IRM/RelationBlankPresent`. Verify: both clean.
- [x] 7.3 Traceability coverage: list every H/E/X ID in `business-rules.md` and every `# <ID> —` comment in `features/funds/lp_portfolio/` and `features/ai/lp_assistant/lp_assistant_portfolio_scope.feature`, and confirm the two sets are equal. Grep `app/` for each code-path ID listed in LLD › Traceability Comments. An edge case found during apply gets a new row in business-rules.md AND a scenario, never a scenario alone. Verify: diff output is empty.
- [x] 7.4 UI/UX self-review against the 18-point checklist, with real browser screenshots of every changed screen (fund form, LP grid with and without own share, LP company page at desktop and phone width, company page notices, dashboard settings with LP layouts, preview, holding page). Verify: screenshots attached to the PR. All six feature files green in one final background pcuc run (`-n 4`).
- [x] 7.6 Gate on the fund manager's modules: fund-portfolios (Features step portfolio settings via `FundFeatureGuard::PORTFOLIO_FLAGS`, `InvestorPolicy#lp_sharing?`, `LpCompanyDashboardPolicy`, `DashboardWidgetPolicy#manage_lp_layouts?`) and KPIs (`DashboardWidget.lp_safe_widget_names`: widget form, validation, starter layout, LP rendering, layout resolver). Covers **E95–E97, X20, X21**.
- [ ] 7.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off.
