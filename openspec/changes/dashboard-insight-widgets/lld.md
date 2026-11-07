# Dashboard Insight Widgets — Low-Level Design

> Additive to [design.md](design.md). Rules and IDs: [business-rules.md](business-rules.md).

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Pattern Conformance](#pattern-conformance)
- [Security Detail](#security-detail)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- 1 model edited (constants only), 6 new helper modules, 17 new partials, 0 migrations, 0 routes, 0 jobs.
- The decisions to check: the visibility gate ([design D3](design.md#d3--hide-for-investor-role)), the query budget
  per widget, link filters equal to count filters ([D5](design.md#d5--needs-attention-filters)), and portable SQL
  ([D4](design.md#d4--bucket-in-ruby-over-grouped-dates)).

**Reviewer checks**
- [ ] No file outside the File Map changed (bar features and step files).
- [ ] `git diff --stat` shows no migration, route or controller change.

---

## File Map

| File | New / Mod | Widgets | Phase |
|---|---|---|---|
| `app/packs/core/base/models/dashboard_widget.rb` | Mod (constants) | all: 20 placements, `INSIGHT_KPI_REPORT_HINTS`, `INSIGHT_FIELD_HINTS`, `WIDGET_HELP` entries | 1 |
| `app/packs/core/base/helpers/insight_widgets_helper.rb` | New | shared gate / settings / empty state / money | 1 |
| `app/packs/startups/kpis/helpers/kpi_insight_widgets_helper.rb` | New | KPI Movers, KPI Threshold Watch, Peer KPI Comparison | 1, 2 |
| `app/packs/core/investors/helpers/company_insight_widgets_helper.rb` | New | Monitoring Status, Investment Timeline, Ownership Trend | 1, 2 |
| `app/packs/funds/portfolios/helpers/portfolio_insight_widgets_helper.rb` | New | Valuation Freshness, Winners & Losers, Sector Exposure | 1, 2 |
| `app/packs/funds/funds/helpers/fund_insight_widgets_helper.rb` | New | Remittance Ageing, NAV per Unit Trend, Hedge Expiries | 1, 2 |
| `app/packs/funds/funds/helpers/investor_ops_insight_widgets_helper.rb` | New | Investor Pending Actions, Side-letter Obligations, Needs Attention | 1, 2 |
| `app/packs/core/base/helpers/ops_insight_widgets_helper.rb` | New | Overdue Tasks by Assignee, Stuck Workflows | 1, 2 |
| `core/investors/views/investors/widgets/_kpi_movers, _kpi_threshold_watch, _monitoring_status, _investment_timeline, _ownership_trend` | New | company widgets | 1, 2 |
| `funds/portfolios/views/aggregate_portfolio_investments/widgets/_valuation_freshness, _winners_losers, _sector_exposure, _peer_kpi_comparison` | New | portfolio widgets | 1, 2 |
| `funds/capital_remittances/views/capital_remittances/widgets/_ageing` | New | Remittance Ageing | 1 |
| `funds/evergreen/views/evergreen/widgets/_nav_per_unit_trend` | New | NAV per Unit Trend | 1 |
| `funds/derivatives/views/derivative_contracts/widgets/_hedge_expiries` | New | Hedge Expiries | 2 |
| `funds/funds/views/funds/widgets/_investor_pending_actions, _needs_attention` | New | investor / ops | 1 |
| `funds/side_letters/views/side_letter_obligations/widgets/_due` | New | Side-letter Obligations | 2 |
| `core/base/views/dashboard_widgets/widgets/_overdue_tasks_by_assignee, _stuck_workflows` | New | ops | 1, 2 |

**Reviewer checks**
- [ ] Every registered `path` resolves to a partial in the map (`bin/rails runner` lookup in Test Plumbing).
- [ ] Widgets reading `funds` models sit in a `funds/*` pack ([D9](design.md#d9--pack-placement)).

---

## Schema Detail

N/A — no schema change. Settings are keys in `dashboard_widgets.metadata` (existing text column, parsed by
`RubyLiteral`).

| Setting key | Type | Default | Widgets |
|---|---|---|---|
| `top_n` | Integer ≥ 1 | 5 (10 for Overdue Tasks) | KPI Movers, Winners & Losers, Overdue Tasks by Assignee |
| `tag_list` | String | "Actual" | KPI widgets |
| `period` | Month/Quarter/Year/YTD | "Quarter" | KPI widgets |
| `period` | quarter/year | "quarter" | Investment Timeline |
| `kpi_name` | String | none — required; blank or missing shows "Set the KPI name in this widget's settings." (X8); the hint suggests Revenue | Peer KPI Comparison |
| `current_days` / `due_days` / `limit` | Integer ≥ 1 | 90 / 180 / 15 | Valuation Freshness |
| `measure` | fmv/cost | "fmv" | Sector Exposure |
| `months` | Integer ≥ 1 | 12 | NAV per Unit Trend |
| `days` | Integer ≥ 1 | 90 / 30 / 7 | Hedge Expiries / Side-letter / Stuck Workflows |
| `limit` | Integer ≥ 1 | 10 | Stuck Workflows |
| `kyc_expiry_days` | Integer ≥ 1 | 60 | Investor Pending Actions |

- If `due_days` < `current_days`, `due_days` is raised to `current_days`, so the Due band is empty rather than inverted.

**Reviewer checks**
- [ ] Each key above has an `INSIGHT_FIELD_HINTS` entry with the same default in its hint.

---

## Method Contracts

| Method | Args | Returns | IDs |
|---|---|---|---|
| `insight_widget_visible?` | — | Boolean | X2, X9 |
| `insight_int_arg(args, key, default)` | Hash, Symbol, Integer | Integer ≥ 1 | E1, E2 |
| `insight_str_arg(args, key, default)` | Hash, Symbol, String | String | X8 |
| `insight_choice_arg(args, key, choices, default)` | Hash, Symbol, Array<String>, String | String | E16, E29 |
| `insight_empty_state(message)` | String | SafeBuffer `<p>` | empty rows |
| `insight_money(cents, currency)` | Integer, String | String | money cells |
| `KpiInsightWidgetsHelper` methods | company/companies + settings | latest report + rows (name, value, change, mapping, flag) | H3–H6, H13, E3–E12, E31–E32 |
| `CompanyInsightWidgetsHelper` methods | company (+ period) | report / `{period_label => {bought:, sold:}}` / `{category => [[date, %], …]}` | H5, H7, H8, E13–E19 |
| `PortfolioInsightWidgetsHelper` methods | company ids or fund + settings | rows with status / two ranked lists / `{sector => cents}` | H9–H12, E20–E30 |
| `FundInsightWidgetsHelper#remittance_ageing(fund)` | Fund | ordered `{bucket => {count:, cents:}}` (all 5 buckets present) | H14, E33–E38 |
| `FundInsightWidgetsHelper` NAV / hedges | fund + months/days | `{unit_type => [[date, nav]]}` / contract rows | H15–H16, E39–E44 |
| `InvestorOpsInsightWidgetsHelper` methods | investor/nil + settings | sections `{count:, rows:, path:}` / cards `[{label:, count:, path:, icon:, color:}]` / obligation rows | H17–H21, H24, E45–E58 |
| `OpsInsightWidgetsHelper` methods | top_n / days, limit | `[[label, count]]` / journey rows | H22–H23, E59–E63 |

- Final signatures are recorded in "Changed during the build" below, once the build settles them.

**Reviewer checks**
- [ ] No helper returns an unloaded relation that a partial iterates with per-row queries.
- [ ] Every helper method has a comment naming its IDs.

### Changed during the build

| Log # | What changed | Why |
|---|---|---|
| B1 | KPI changes print as the KPI grid prints them ("-30.0 %", "12.5 %"), not "−30.00 %" | `kpi_percentage_class` / `kpi_percentage_display` reused (D7); one format everywhere |
| B2 | Investment Timeline: a row without `entity_currency_amount_cents` uses `amount_cents` when its fund is in the firm's currency; otherwise it is left out and the widget footnotes "N transaction(s) in another currency without a INR amount yet" | `entity_currency_amount_cents` is filled by `TrackingCurrencyJob`, so it can lag |
| B3 | Investment Timeline: zero-amount rows create no period | No empty bars |
| B4 | Ownership Trend is gated on the Cap Table module (`policy(ShareholderPosition).index?`) and reads approved positions only | Same access as the cap-table screens |
| B5 | Extra empty states: KPI Movers "No KPI on the {date} report has a change against an earlier report yet."; Peer KPI "No company here has {KPI} on its latest {tag} {period} KPI report."; Winners & Losers "No holding is above cost."; Sector Exposure (cost) "No holding has a remaining cost yet."; Valuation Freshness "This fund holds no portfolio companies." / "No portfolio companies match the filters." | Every empty path needs a sentence (spec: Empty widgets explain why) |
| B6 | Valuation Freshness: `due_days` below `current_days` is raised to `current_days` | Keeps the bands ordered (already in Schema Detail) |
| B7 | NAV window: from the month end `months` back (exclusive) to the latest approved NAV; 6 months from 30 Sep plots Apr–Sep | Whole months |
| B8 | Remittance Ageing: a call with no due date counts as "Not yet due" | Can't be overdue without a date |
| B9 | Stuck Workflows: a journey with no `current_step_since` is never listed (101 of 174 active in 157) | Its wait is unknown |
| B10 | Needs Attention: a card is hidden when the viewer may not open its list (that model's `index?` policy) | A card must link somewhere the viewer can go |
| B11 | Open e-sign count for a non-admin covers only the documents the documents list shows them | Count = list (H21) |
| B12 | Investor Pending Actions' Unpaid calls link filters the remittances list by status and investor name (the list has no investor-id filter) | Two LPs with the same name would share the link — noted for review |
| B13 | Side-letter Obligations need the firm's `side_letter_obligation_agent` flag; without it the empty state shows | Obligations exist only with that module |
| B14 | Document rows load `send_email`, `approved`, `template`, `sent_for_esign` too | `Document` sets these flags on load; a narrower select raised `MissingAttributeError` |
| B15 | E37 is tested by running the link's own query through `CapitalRemittanceList` and comparing counts, not by clicking | Same assertion, no grid JS in rack_test |
| B16 | Needs Attention's "Imports with errors" card and its `import_days` setting removed (user request, 2026-11-07); E56 withdrawn, H19/H20/E58 now four cards | Fewer cards; failed imports stay visible on the Import Uploads list |

---

## Controllers, Params and Responses

N/A — no controller, action, route or param is added. Widgets render inside existing pages
(`FundsController#dashboard`, `InvestorsController#dashboard`, `DashboardWidgetsController#dashboard`,
`InvestorsController#index` multi-portfolio, `EntitiesController` home).

**Reviewer checks**
- [ ] `git diff config/routes*` is empty.

---

## Queries and Indexes

| Widget | Query shape | Index used | Large-table rule |
|---|---|---|---|
| Remittance Ageing | `fund.capital_remittances.joins(:capital_call).where(status: %w[Pending Overdue]).group("capital_calls.due_date").pluck(due_date, COUNT(*), SUM(call+fee−collected))` | `capital_remittances.fund_id` | grouped; ≤ number of calls rows reach Ruby |
| Needs Attention | 5 × `policy_scope(M).where(...).count` | entity_id indexes | COUNT only |
| Investor Pending Actions | per section `count` + `limit(5)` with `includes` | `investor_id` | no full load |
| Valuation Freshness | `Valuation.where(entity_id:, owner_type: "Investor", owner_id: ids).group(:owner_id).maximum(:valuation_date)` | `owner_type, owner_id` | one row per company |
| Winners & Losers / Sector | `aggregate_portfolio_investments` grouped SUM | `fund_id` | grouped |
| KPI widgets | latest `kpi_reports` id by `as_of DESC LIMIT 1`; `kpis.where(kpi_report_id:).select(:id, :name, :value, :percentage_change, :rag_status, :portfolio_company_id)` | `kpi_report_id` | narrow select |
| Investment Timeline | `policy_scope(PortfolioInvestment).where(portfolio_company_id:).pluck(:investment_date, :quantity, :entity_currency_amount_cents)` | `portfolio_company_id` | ≤ few hundred rows per company |
| Stuck Workflows | `policy_scope(WorkflowInstance).instance_active.where(current_step_since: ..cutoff).order(:current_step_since).limit(n).includes(:workflowable, :workflow_template)` | — | limited |

- Every `distinct`/`group` is preceded by `unscope(:order)` where the model has a default order.
- No `DATEDIFF`, `DATE_FORMAT` or `IF()`: buckets and periods are made in Ruby.

**Reviewer checks**
- [ ] Each query ran once against dev MySQL (entity 157) without an ONLY_FULL_GROUP_BY error.
- [ ] No `.pluck(...).uniq`, no `.present?`/`.blank?` on a relation (IRM/RelationBlankPresent passes).

---

## Transactions, Locking and Concurrency

N/A — read only.

**Reviewer checks**
- [ ] No `save`, `update`, `create` or `destroy` call in any new helper or partial.

## Background Jobs

N/A — none.

**Reviewer checks**
- [ ] No new file under `*/jobs/`.

## External Integrations

N/A — none (the portco agent's stored report is read, not called).

**Reviewer checks**
- [ ] No `LlmService` or HTTP call in the new code.

---

## Error Mapping and Logging

| Condition | Behaviour |
|---|---|
| Non-literal metadata | Existing `metadata_args` logs and returns `{}` → defaults |
| Bad setting value | Default used silently (E1, E2) |
| No data | Empty-state sentence |
| Missing agent / KPI module | Widget not rendered (X4, E8) |

**Reviewer checks**
- [ ] No `rescue` that hides a query error in the new helpers.

---

## Security Review

- No new entry point. The surface is the rendered HTML of existing authorized pages.
- Investor-role users are refused at the partial level ([D3](design.md#d3--hide-for-investor-role)).

**Reviewer checks**
- [ ] `grep -L "insight_widget_visible?"` over the 17 partials prints nothing.
- [ ] Brakeman shows no new warning.

---

## Configuration and Rollout

- Opt-in: Settings › Widgets › New. No flag.
- Default-catalogue side effect: dashboards with nothing configured list every widget, new ones included (A10).
- Wave 1 (8 widgets) and wave 2 (9 widgets) ship together; tasks.md phases follow the feature files.

**Reviewer checks**
- [ ] FM Landing default still shows exactly the first 4 widgets.

---

## Test Plumbing

- Shared steps: `today is {string}` (travel_to), `the {string} widget on the {string} has settings {string}`,
  `I open the company dashboard of {string}`, `I open the {string} of fund {string}`.
- New step files: `dashboard_insight_company_steps.rb`, `dashboard_insight_fund_steps.rb`,
  `dashboard_insight_ops_steps.rb`, `dashboard_insight_common_steps.rb`.
- Runs: up to 4 background processes with TEST_ENV_NUMBER 47101–47104, distinct feature files each.

**Reviewer checks**
- [ ] `bundle exec cucumber --dry-run` over the 10 files: no undefined or ambiguous steps.

---

## Pattern Conformance

| Pattern (design table) | Conforms? | Evidence |
|---|---|---|
| Pack boundaries | Yes | File Map |
| Reuse before add | Yes | `WidgetCardComponent`, `_report_detail`, `kpi_percentage_class`, `tasks/_stats` markup |
| Queries and data | Yes | Queries and Indexes |
| UI | Yes | No new CSS/JS files |

**Reviewer checks**
- [ ] `git diff --stat -- app/assets app/javascript` is empty.

---

## Security Detail

| Surface | Policy method | Scope used to load | Params | Covered by |
|---|---|---|---|---|
| Fund Dashboard widgets | `FundPolicy#dashboard?` (existing) + gate | `fund.<assoc>` | — | X9 |
| Portfolio / Aggregated widgets | `FundPolicy#dashboard?` / `InvestorPolicy#index?` + gate | fund holdings / page `investors` | — | X2, X7 |
| Company widgets | `InvestorPolicy#dashboard?` + gate | `policy_scope(KpiReport)`, `policy_scope(PortfolioInvestment)`, company associations | — | X5, X6 |
| Investor widgets | `InvestorPolicy#dashboard?` + gate | `policy_scope` per model, `investor_id:` | — | X10 |
| Ops / FM landing widgets | `DashboardWidgetPolicy#dashboard?` + gate | `policy_scope` per model | — | X3, X11 |
| LP layout | `lp_safe_in_lp_layout` validation (existing) | — | — | X1 |

**Reviewer checks**
- [ ] Every cross-record query in Ops/Investor/KPI helpers starts from `policy_scope(...)`.

---

## Project Rules Checklist

| Rule (CLAUDE.md / memory) | Applies | How |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | `exists?`/`none?`/`count` only |
| Dedup in SQL | Applies | `distinct`/`group` in SQL |
| Batch bulk ops | N/A | read only |
| Select needed columns on `account_entries` | N/A | not read |
| No speculative eager loads | Applies | preloads only on the ≤ limit rows shown |
| Doc-generation relation contexts | N/A | — |
| Dates via `l(...)`, no human `strftime` | Applies | all dates in partials |
| Email date format | N/A | no email |
| JS dates via `locale_date_format.js` | N/A | no JS |
| MCP ontology | N/A | no ransackable change |
| Tenant scoping | Applies | owner / `policy_scope` |
| `unscope(:order)` before DISTINCT (MySQL) | Applies | Queries |
| Inline comments + ID comments | Applies | every helper |
| Cucumber only | Applies | 10 features |

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
