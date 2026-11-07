# Tasks

> Phases follow the feature files, not the waves: each phase closes with its own green Cucumber run. Wave 1 and wave 2
> widgets ([recommendations §5](../../../../docs/modules/dashboards/widget_recommendations.md#5-wave-1-shortlist-being-built))
> are spread across phases 2–5. IDs come from [business-rules.md](business-rules.md).

## 1. Catalogue and shared helper

- [x] 1.1 Register the 20 placements, `INSIGHT_FIELD_HINTS` and `WIDGET_HELP` entries in `DashboardWidget` (LLD › File Map); verify with `bin/rails runner` that every dashboard lists its new widgets and `DashboardWidget.field_hint("KPI Movers", "top_n")` returns the label
- [x] 1.2 Add `InsightWidgetsHelper` (gate, settings, empty state, money) (LLD › Method Contracts); verify it loads in `bin/rails runner`
- [x] 1.3 UI review — no screens in this phase beyond the widget form; check the New Widget form lists the new types with labelled settings
- [x] 1.4 N+1 check — run phase 1's feature with `PROSOPITE=1`; `log/prosopite.log` has no entry from this change's code
- [x] 1.5 Write `features/core/dashboard_insight_widgets_common.feature` (H1, H2, E1, E2, X1, X2) and run `TEST_ENV_NUMBER=47101 bundle exec cucumber features/core/dashboard_insight_widgets_common.feature` until green before phase 2

## 2. Company widgets (Portfolio Company Dashboard)

- [x] 2.1 KPI Movers + KPI Threshold Watch partials and `KpiInsightWidgetsHelper` (LLD › Method Contracts, Queries); verify queries on dev MySQL for a 157 company with Actual Quarter KPIs
- [x] 2.2 Monitoring Status partial reusing `portfolio_company_dashboard/_report_detail` (design D6); verify a 157 company with a PortfolioCompanyAgent report renders its issues
- [x] 2.3 Investment Timeline + Ownership Trend partials and `CompanyInsightWidgetsHelper` (design D8); verify on dev MySQL
- [x] 2.4 UI review — screenshot the company dashboard of a 157 company beside `capital_calls/widgets/_collection_status` (card) and apply the UI self-review checklist
- [x] 2.5 N+1 check — `PROSOPITE=1` run of phase 2's features; fix entries from this change
- [x] 2.6 Write `features/startup/dashboard_insight_company_widgets.feature` (H3–H8, E3–E19, X4) and `features/security/dashboard_insight_company_isolation.feature` (X5, X6); run `TEST_ENV_NUMBER=47102 bundle exec cucumber` on both until green before phase 3

## 3. Portfolio widgets (Portfolio + Aggregated dashboards)

- [x] 3.1 Valuation Freshness (both dashboards), Winners & Losers, Sector Exposure partials and `PortfolioInsightWidgetsHelper` (design D4); verify on dev MySQL for a 157 fund
- [x] 3.2 Peer KPI Comparison partial (Aggregated) in `KpiInsightWidgetsHelper`; verify on dev MySQL
- [x] 3.3 UI review — screenshot the fund Portfolio tab and the Aggregated Portfolio Dashboard; apply the checklist
- [x] 3.4 N+1 check — `PROSOPITE=1` run of phase 3's features
- [x] 3.5 Write `features/fund/dashboard_insight_portfolio_widgets.feature` (H9–H12, E20–E30), `features/fund/dashboard_insight_peer_kpi.feature` (H13, E31, E32, X8) and the X7 row of `features/security/dashboard_insight_fund_isolation.feature`; run `TEST_ENV_NUMBER=47103 bundle exec cucumber` on them until green before phase 4

## 4. Fund capital widgets (Fund Dashboard)

- [x] 4.1 Remittance Ageing partial and `FundInsightWidgetsHelper#remittance_ageing` with the matching "View open remittances" link (design D4, ⑦); verify on dev MySQL that the bucket counts add up to the Pending + Overdue count of a 157 fund
- [x] 4.2 NAV per Unit Trend and Hedge Expiries; verify on fund 350 (NAVs) and a fund with open contracts
- [x] 4.3 UI review — screenshot the Fund Dashboard; apply the checklist
- [x] 4.4 N+1 check — `PROSOPITE=1` run of phase 4's features
- [x] 4.5 Write `features/fund/dashboard_insight_fund_widgets.feature` (H14–H16, E33–E44) and the X9 row of the fund isolation feature; run `TEST_ENV_NUMBER=47104 bundle exec cucumber` until green before phase 5

## 5. Investor and Ops widgets

- [x] 5.1 Investor Pending Actions + Side-letter Obligations partials and `InvestorOpsInsightWidgetsHelper`; verify on dev MySQL for a 157 LP
- [x] 5.2 Needs Attention (Ops + FM Landing) with links whose filters equal the counts (design D5); verify each count equals the linked list's row count for a 157 admin
- [x] 5.3 Overdue Tasks by Assignee + Stuck Workflows in `OpsInsightWidgetsHelper`; verify on dev MySQL
- [x] 5.4 UI review — screenshot Ops Dashboard, FM Landing and an Investor Dashboard; apply the checklist
- [x] 5.5 N+1 check — `PROSOPITE=1` run of phase 5's features
- [x] 5.6 Write `features/core/dashboard_insight_investor_widgets.feature` (H17, H18, E45–E53), `features/core/dashboard_insight_ops_widgets.feature` (H19–H24, E54–E63) and `features/security/dashboard_insight_ops_isolation.feature` (X3, X10, X11); run `TEST_ENV_NUMBER=47101 bundle exec cucumber` on them until green before phase 6

## 6. Demo setup, coverage and docs

- [x] 6.1 Enable every new widget for entity 157 on the dev DB (layout "Default") and screenshot each dashboard; save the screenshots under the scratchpad and list them in the hand-off
- [x] 6.2 Coverage — list every H/E/X ID in business-rules.md and every `# <ID> —` comment in the 10 feature files; the two sets are equal
- [x] 6.3 Update design.md / lld.md "Changed during the build" with any deviation, and the recommendations doc's assumptions
- [x] 6.4 Rubocop + Brakeman clean on the changed files
- [ ] 6.5 QA runs qa-checklist.md on a deployed build and records the sign-off (for QA, not the apply agent)

## Apply log

- All 140 scenarios (98 H/E/X rows; outlines expand) green across 10 feature files; reruns after fixes: `table.rows` → `table.raw` in fund/ops steps, purchase-date valuations removed in portfolio setup, e-sign card link given `entity_id`.
- `PROSOPITE=1`: 140/140 green. 3 N+1 reports, all in **existing** list pages the Needs Attention links open (not this change's code): `investor_kycs/_stats.html.erb:19` (one COUNT per stat card) and `e_signatures/_e_signature_stats.html.erb:87` (one COUNT per card). Left unchanged — shared code.
- Coverage: 98 IDs in business-rules.md = 98 `# ID —` comments in the features; no gaps, no duplicates.
- RuboCop: 12 Ruby files, no offenses.
- Entity 157 (dev DB): 24 `dashboard_widgets` rows created (20 new widgets + the Ops Dashboard's 4 defaults kept visible); ids in the session scratchpad `created_widget_ids.txt` for removal. Peer KPI Comparison set to `{kpi_name: "Revenue"}`.
- Screenshots of every widget on entity 157 taken in-process (Warden `login_as`, no data written). UI review against `capital_calls/widgets/*` cards and `tasks/_stats`: same card, table and stat-card styling; ⓘ on every title; empty states centred. Polish items left for the user: losses print as "₹-35,97,…" (the app's money formatter); long Investment Timeline tables; Medium widgets beside a taller neighbour leave blank space (row height); Ownership Trend renders nothing without the Cap Table module, leaving an empty slot.
- 2026-11-07 follow-ups from the user's UI review: every widget table now uses the regular app table markup (`table table-bordered dataTable`, as `tasks/_index`), with headings on Winners & Losers and Investor Pending Actions; Investor Pending Actions gained a help line per section, count tooltips and column ⓘ tooltips; Needs Attention's "Imports with errors" card and `import_days` setting removed (B16, E56 withdrawn — 97 IDs = 97 scenario comments). Runs: 140/140 after the table change; investor + ops + common + ops isolation 78/78 after the help text; ops + common + ops isolation 64/64 after the card removal.
- 2026-11-07 (after commit 88d50ef196): help line, column ⓘ tooltips and card tooltips on the other 16 widgets (shared `insight_help_line` / `insight_th` in `InsightWidgetsHelper`), richer title help; Valuation Freshness "Days since" → "Age" (days ≤ 30, then months, then years + months; exact days on hover — E64); the existing Company Charts widget's tables moved to the regular app table markup, its 500 px inner scroll removed, and its "Other" items shown as ordinary expandable rows (`company_sector_toggle_controller.js`). Runs: 138/138 insight scenarios; `features/misc/multiple_portfolio_dashboard.feature` 3/3; dev-DB render check of 9 dashboards and every widget frame: 0 errors.
