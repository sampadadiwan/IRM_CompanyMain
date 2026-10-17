# LP Folio Portfolio & Company Dashboard — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Business rules (H/E/X)](business-rules.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document adds to [design.md](design.md). It links to
> design's diagrams and worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions and ends with
> **Reviewer checks** to tick.

> **Existing-model changes: approved by the user on 2026-10-14** (design.md
> [Changes to existing models](design.md#changes-to-existing-models)).

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [UX Reuse Map](#ux-reuse-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Traceability Comments](#traceability-comments)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **The investor-scope SQL condition** (`fund_id IN (whole-fund ids) OR id IN (visible ids)`) is the
  riskiest line in the change. → [Queries and Indexes](#queries-and-indexes), X17/E9/H1/H2.
- **Membership pairs each commitment with its own fund's allocation formula.** Feeder commitments
  use the feeder fund's formula, not the master's. → [Method Contracts](#method-contracts) (`LpFolioAllocationQuery`), E28a.
- **Own share uses `ROW_NUMBER()` per subject, not `MAX(reporting_date)` per holding.** → [Queries and Indexes](#queries-and-indexes), E33.
- **Layout resolution runs in Ruby over at most a few layout names per entity**, never per widget
  row. → `LpLayoutResolver`, E81–E85.
- **The helper's existing user-tag merge must be bypassed in LP context.** Otherwise an LP user's
  own tags would unlock widgets. → `DashboardWidgetsHelper#dashboard_widgets`, E87.
- **Feature bits append at positions 11 and 12.** The parallel `fund-market-data` change may also
  append bits, so re-check `Fund.features` on main before merging. → [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

Grouped by design box. Pack layout follows existing neighbours.

| Box | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/funds/funds/models/concerns/fund_enabled.rb` | Modified | Append `lp_folio_portfolio`, `lp_own_share` to the `flag :features` list; `lp_portfolio_view` reader/writer |
| ① | `app/packs/funds/funds/models/lp_portfolio_view.rb` | New | Value object: option ↔ flags, `OWN_SHARE_RULE_TYPES`, validation of picks |
| ① | `app/packs/funds/funds/models/fund.rb` | Modified | `belongs_to :lp_allocation_fund_formula` / `:lp_fmv_fund_formula` (optional); `validate` via `LpPortfolioView`; `lp_own_share_ready?` |
| ① | `app/packs/funds/funds/controllers/funds_controller.rb` | Modified | Permit `lp_portfolio_view`, `lp_allocation_fund_formula_id`, `lp_fmv_fund_formula_id`; flash the E1 warning |
| ① | `app/packs/funds/funds/views/funds/_features.html.erb` | Modified | Dropdown + two pickers replacing the "Show fund portfolios to LPs" checkbox; ⓘ tooltip (E79) |
| ① | `db/migrate/*_add_lp_portfolio_picks_to_funds.rb` | New | Two FK columns + indexes |
| ③ | `app/packs/funds/portfolios/services/lp_portfolio_visibility.rb` | New | The visible-set service (design card ③) |
| ③ | `app/packs/funds/portfolios/services/lp_folio_allocation_query.rb` | New | Membership and own-share SQL |
| ③ | `app/packs/funds/portfolios/services/lp_portfolio_visibility_cache.rb` | New | `ActiveSupport::CurrentAttributes` holding the per-request visibility memo (kept out of `Current`, which by its own rule holds only the acting user) |
| ④ | `app/packs/funds/portfolios/policies/portfolio_investment_policy.rb` | Modified | Investor branch of `Scope#resolve` and `show?` |
| ④ | `app/packs/funds/portfolios/policies/aggregate_portfolio_investment_policy.rb` | Modified | Same. Remove `toggle_show_portfolio?` |
| ④ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/_index.html.erb` (+ grid partial it renders) | Modified | LP banner, Your columns, totals row, company link via `openable?` |
| ④ | `app/packs/core/base/models/dashboard_widget.rb` | Modified | `LP_ALLOCATED_PORTFOLIO_WIDGETS`; also ⑤ constants |
| ④⑥ | `app/packs/core/base/helpers/dashboard_widgets_helper.rb` | Modified | `lp_context:` / `lp_portfolio_view:` keywords; skip user tags and fallback in LP context |
| ⑤ | `app/packs/core/base/services/lp_layout_resolver.rb` | New | Picks the LP layout for a company from tags |
| ⑤ | `app/packs/core/base/controllers/dashboard_widgets_controller.rb` | Modified | `setup_lp_layout`, `new_lp_layout`; LP-safe type list on `new`/`edit` for LP layouts |
| ⑤ | `app/packs/core/base/views/dashboard_widgets/{index,_index,_form,_dashboard_selector}.html.erb` | Modified | Guidance notices, selector labels, Tags help, Set up / New LP layout buttons |
| ⑤ | `app/packs/core/investors/controllers/investors_controller.rb` | Modified | `lp_sharing` action |
| ⑤ | `app/packs/core/investors/policies/investor_policy.rb` | Modified | `lp_sharing?` |
| ⑤ | `app/packs/core/investors/views/investors/show.html.erb` | Modified | Show/Hide from LPs in the button bar, Preview as LP in Misc, header notices, Visible to LPs badge |
| ⑤ | `app/packs/core/investors/views/investors/_lp_sharing_notice.html.erb` | New | The company-page guidance notice (layout used / tie / none / all hidden) |
| ⑤ | `app/packs/funds/portfolios/views/aggregate_portfolio_investments/_show.html.erb` | Modified | Remove Preview, Show/Hide Portfolio and the attribute row; E80 notice; Widgets/Track Record tabs removed |
| ⑤ | `app/packs/funds/portfolios/controllers/aggregate_portfolio_investments_controller.rb` | Modified | Remove `toggle_show_portfolio`; investor redirect in `show` |
| ⑤ | `config/routes/fund.rb`, `config/routes/core.rb` | Modified | Drop `toggle_show_portfolio`; add `lp_sharing`, `setup_lp_layout`, `new_lp_layout`, LP company dashboard routes |
| ⑤ | `db/migrate/*_add_show_to_lps_to_investors.rb` | New | Column |
| ⑤ | `db/migrate/*_carry_over_show_portfolio_to_companies.rb` | New | Data carry-over (idempotent, reversible no-op) |
| ⑤ | `db/migrate/*_widen_dashboard_widgets_name.rb` | New | `name` limit 20 → 100 |
| ⑥ | `app/packs/funds/portfolios/controllers/lp_company_dashboards_controller.rb` | New | `show`, `preview`, `widget` |
| ⑥ | `app/packs/funds/portfolios/policies/lp_company_dashboard_policy.rb` | New | `show?`, `preview?`, `widget?` |
| ⑥ | `app/packs/funds/portfolios/views/lp_company_dashboards/{show,_holdings_card,_fund_selector,_refusal,_preview_modal}.html.erb` | New | Page parts |
| ⑥ | `app/packs/core/base/views/dashboard_widgets/_dashboard.html.erb` | Modified | LP mode: no Reports dropdown, no layout selector |
| ⑥ | `app/packs/core/documents/views/documents/_embed.html.erb` | Modified | `document.video?` branch → `layouts/video` |
| ⑦ | `app/packs/funds/portfolios/services/lp_widget_data.rb` | New | Per-widget LP loaders (KPIs Actual, valuations, stats by fund) |
| ⑦ | `app/packs/ai/lp_assistant/tools/run_query_tool.rb` | Modified | `{VISIBLE_API_IDS}` / `{VISIBLE_PI_IDS}` required for portfolio tables |
| ⑦ | `app/packs/ai/lp_assistant/services/lp_chat_provider.rb` | Modified | Supply visible ids from ③ |
| ⑦ | `app/packs/ai/lp_assistant/skills/portfolio.md` | Modified | Describe placeholders and company `show_to_lps` |
| tests | `features/funds/lp_portfolio/*.feature`, `features/ai/lp_assistant/lp_assistant_portfolio_scope.feature`, `features/step_definitions/lp_portfolio_steps.rb` | New | See [Test Plumbing](#test-plumbing) |
| docs | `docs/user_guides/portfolio_investments_user_guide.md`, the dashboard widgets user guide | Modified | LP view, LP layouts, FAQs (per the user-guide FAQ standard) |

**Reviewer checks**
- [ ] Every class in design's class diagram has a file here (Fund, LpPortfolioView, LpPortfolioVisibility, LpFolioAllocationQuery, two policy scopes, Investor, DashboardWidget, InvestorsController, DashboardWidgetsController, LpLayoutResolver, LpCompanyDashboardsController, LpCompanyDashboardPolicy, LpWidgetData, RunQueryTool)
- [ ] New files sit in the same pack as their nearest existing neighbour (Packwerk: `funds/portfolios` may use `core/base`, never the reverse)

---

## UX Reuse Map

Every new UI element copies an existing screen, partial or helper. No new CSS, colours or components.

| New element | Reuses | Where it lives today |
|---|---|---|
| Show / Hide from LPs button | Outline button in the company page button bar | `investors/show.html.erb` (Edit / Delete / Misc bar) |
| Preview as LP… | A `dropdown-item` with `data-bs-toggle="tooltip"` in the Misc dropdown | `investors/show.html.erb` Misc menu (CapTable, Dashboard items) |
| Preview picker modal | Bootstrap modal with a form, as in the workflow launch modal | `investors/_workflow_summary.html.erb` |
| Hide from LPs confirm | Action-summary confirm card ("Immediate Actions" bordered block) in a Bootstrap modal | `startups/kpis/views/kpi_reports/_grid_view.html.erb` (~line 171) |
| "Visible to LPs" badge | `badge bg-success-subtle text-success` with a `ti` icon | Used in 24 views (e.g. access rights rows) |
| Guidance notices | `alert alert-info` / `alert alert-warning d-flex align-items-start gap-2` with a `ti` icon | 26 / 3 existing uses |
| Tooltips | `data-bs-toggle="tooltip"` + `data-bs-title` | `investors/show.html.erb`, `access_rights/_access_right.html.erb` |
| Fund dropdown + pickers reveal | `conditional-visibility` Stimulus controller | `custom_notifications/_form.html.erb` |
| LP company page frame | `dashboard_widgets/_dashboard` (nav pills, widget grid, `WidgetCardComponent`) | `core/base/views/dashboard_widgets/` |
| Holdings card | Row layout of `aggregate_portfolio_investments/_card_table2` | `funds/portfolios/views/aggregate_portfolio_investments/` |
| Fund selector | `form-select` in a `turbo_frame` that reloads only the card and widgets, like `_dashboard_selector` | `dashboard_widgets/_dashboard_selector.html.erb` |
| LP portfolio banner and totals row | `alert alert-info` + the grid's existing footer/total row pattern | API grid partials |
| Refusal page | Existing access-denied partial style (`alert alert-warning` in a card) | — (copy the layout of an existing Pundit refusal) |
| Video in Embed Document | `layouts/video` partial | `documents/show.html.erb:5-6` |

**Navigation (easy to find):**
- LP: Fund › Portfolio › company name → LP Company Dashboard. The page starts with a way back to the
  fund ("Growth Fund I › Portfolio › Acme Robotics"). Use the breadcrumb pattern the LP fund pages
  already render; if they have none, use a plain "← Growth Fund I portfolio" link styled like the
  existing back links. Check this during apply. The nav pills jump between widgets.
- Fund team: company page → Show to LPs, Misc › Preview as LP, notice → Open layout → dashboard
  settings with the LP layout preselected. Dashboard settings notice → Preview as LP link back.
  Every guidance notice carries a link to the next place to act.

**Reviewer checks**
- [ ] No new CSS file, no inline colours, only Bootstrap `success`/`info`/`warning`/`secondary` variables
- [ ] Every guidance notice has a link to the place where the fix happens
- [ ] Screenshots of each changed screen taken in a real browser before sign-off (UI/UX self-review checklist)

---

## Schema Detail

**`funds`** (existing): stores the two formula picks. The view itself lives in the existing `features` bigint.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `features` | Two bits appended (positions 11, 12: `lp_folio_portfolio`, `lp_own_share`) | bigint | — | no | 0 | — | Same column as `show_portfolios`. No DDL |
| `lp_allocation_fund_formula_id` | Added | bigint | — | yes | NULL | `index_funds_on_lp_allocation_fund_formula_id`; FK `fund_formulas`, `on_delete: :nullify` | Nullable because only *Allocated* views need it. Nullify keeps fund rows valid when a formula is deleted (E6a) |
| `lp_fmv_fund_formula_id` | Added | bigint | — | yes | NULL | `index_funds_on_lp_fmv_fund_formula_id`; FK as above | Same, for the own-share view (E6) |

**`investors`** (existing): the company-level switch.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `show_to_lps` | Added | boolean | — | no | false | none | Read per company render by primary key. Not filtered in lists, so no index |

**`dashboard_widgets`** (existing): layout names carry tags.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `name` | Changed from limit 20 | string | 100 | as today | "Default" | — | "LP, <company tags>". Company `tag_list` is 120 characters, and 100 covers realistic multi-tag names. Validation length matches |

**Migration safety:**
- `funds`, `investors` (~8.7k rows) and `dashboard_widgets` (~300 rows) are small, so a plain `ALTER`
  is instant.
- The carry-over migration is one `UPDATE … WHERE id IN (SELECT DISTINCT …)`. Its `down` is a no-op,
  logged. It prints `changed=N skipped=M`.
- Order: widen `name` → add columns → carry-over.
- `db/schema.rb` and `db/schema_test.rb` are both updated by hand per the local schema-drift practice
  (don't migrate the shared dev DB from this branch without asking).

**Reviewer checks**
- [ ] Both new FKs have indexes. `on_delete: :nullify` is matched by the E6/E6a behaviour
- [ ] `DashboardWidget` validates `name` length ≤ 100
- [ ] Carry-over restricted to `snapshot = FALSE AND deleted_at IS NULL` holdings and non-deleted investors (E51, X19)
- [ ] schema.rb and schema_test.rb both carry the changes

---

## Method Contracts

**`LpPortfolioView`** (value object)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.from_flags(features)` | `ActiveFlag::Value` | `:hidden \| :whole_fund \| :allocated \| :allocated_with_share` | — | — | Yes |
| `.apply(fund, option)` | `Fund`, Symbol/String | — | `ArgumentError` on unknown option | Sets/unsets `show_portfolios`; sets the new bits only when the option needs them, leaving them as they are for `:hidden` (lifecycle table) | Yes |
| `.validate(fund)` | `Fund` | adds to `fund.errors` | — | — | Yes |
| `OWN_SHARE_RULE_TYPES` | — | `%w[AllocatePortfolioInvestment AllocateMasterFundPortfolioInvestment AllocateAggregatePortfolios]` | — | — | — |

**`Fund`** (model additions)

| Method | Returns | Notes |
|---|---|---|
| `#lp_portfolio_view` / `#lp_portfolio_view=` | Symbol | Delegates to `LpPortfolioView` |
| `#lp_own_share_ready?` | Boolean | View is `:allocated_with_share` and both formula ids present |
| `#lp_folio_allocation_warning?` | Boolean | `account_entries.where(fund_formula_id: lp_allocation_fund_formula_id).where.not(capital_commitment_id: nil).none?`, as one `SELECT 1 … LIMIT 1` (E1) |

**`LpPortfolioVisibility`** (service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_user(user)` | investor-role `User` | instance, memoised in `LpPortfolioVisibilityCache` for the request | — | — | Yes |
| `.for_investor(investor, entity:)` | `Investor` (LP), `Entity` | instance (preview, not memoised) | `Pundit::NotAuthorizedError` if `investor.entity_id != entity.id` | — | Yes |
| `#visible_api_ids(fund)` | `Fund` | `Array<Integer>` (`nil` = all, for whole-fund) | — | Lazy one-time membership query | Yes |
| `#visible_pi_ids(fund)` | `Fund` | `Array<Integer>` / `nil` | — | — | Yes |
| `#visible_company_ids(fund)` | `Fund` | `Array<Integer>` | — | — | Yes |
| `#qualifying_funds_for(company)` | `Investor` | `Array<Fund>` by name | — | — | Yes |
| `#openable?(company, fund)` | `Investor`, `Fund` | Boolean | — | — | Yes |
| `#folio_labels(fund)` | `Fund` | `Array<String>` (folio_ids) | — | — | Yes |
| `#own_share(fund)` | `Fund` | `{api_id => {cost: Money, fmv: Money \| nil}}`, `missing: [api_id]` | — | Lazy one query per fund | Yes |

**`LpFolioAllocationQuery`** (query object)

| Method | Arguments | Returns | Notes |
|---|---|---|---|
| `.membership(pairs)` | `Array<[commitment_id, fund_formula_id]>` | `Array<[parent_type, parent_id]>` | Pairs from each commitment's own fund (feeders use the feeder's formula) |
| `.own_share(commitment_ids, formula_ids)` | ids | rows `{parent_type, parent_id, fund_formula_id, amount_cents}`, already latest-per-subject | `ROW_NUMBER()` query |

**`LpLayoutResolver`** (service)

| Method | Arguments | Returns | Notes |
|---|---|---|---|
| `.for(company)` | portfolio-company `Investor` | `Result(name:, matched_tags:, tie_with:, fallback:)`, or `nil` when no usable LP layout | One query: `DashboardWidget.enabled.where(dashboard_name: PORTFOLIO_COMPANY_DASHBOARD, entity_id: company.entity_id).distinct.pluck(:name)`, then Ruby parse/score |

**`DashboardWidget`** (model additions)

| Method | Returns | Notes |
|---|---|---|
| `.lp_layout_name?(name)` | Boolean | Tokens split on `,`, stripped and downcased, include `"lp"` |
| `.lp_layout_tags(name)` | `Array<String>` | Tokens other than `lp` |
| `.lp_layouts_for(entity)` | Relation | Portfolio Company Dashboard rows whose name passes `lp_layout_name?`. Filtered in Ruby on the distinct names, then `where(name: names)` |
| validation `lp_safe_in_lp_layout` | — | On create and on `name` change: if `lp_layout_name?(name)` and `widget_name ∉ LP_SAFE_WIDGET_NAMES` → error "This widget can't be added to an LP layout: it isn't safe to show LPs." (X6) |

**`LpWidgetData`** (service)

| Method | Arguments | Returns | Raises |
|---|---|---|---|
| `.for(widget, company:, fund:, visibility:)` | `DashboardWidget`, `Investor`, `Fund`, `LpPortfolioVisibility` | locals Hash for the widget's partial | `ArgumentError` for a non-LP-safe widget (defence in depth) |

**Reviewer checks**
- [ ] `apply(:hidden)` never clears the new bits (E3), and `apply(:whole_fund)` clears both
- [ ] `own_share` reports a missing FMV, never a missing cost, for a visible holding (E38)
- [ ] `LpLayoutResolver` returns `nil`, not "LP", when "LP" has no enabled widgets (E54, E85)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `FundsController#update` | add `:lp_portfolio_view, :lp_allocation_fund_formula_id, :lp_fmv_fund_formula_id` | `update?` (unchanged) | redirect + flash; warning flash for E1 | 422 + form errors (X1–X5) |
| `InvestorsController#lp_sharing` | `show_to_lps` (boolean) | `lp_sharing?` | redirect to `investor_path`, flash "Shared with LPs" / "Hidden from LPs" | `Pundit::NotAuthorizedError` → standard refusal (X7, X8) |
| `DashboardWidgetsController#setup_lp_layout` | — | `create?` on a new `DashboardWidget` | redirect to index with `name: "LP"` | refusal |
| `DashboardWidgetsController#new_lp_layout` | `tag` (string ≤ 90) | `create?` | redirect to the new layout | flash "An LP layout for this tag already exists." |
| `DashboardWidgetsController#create/update` | add nothing new (`name` already permitted) | as today | as today | 422 with the X6 message |
| `LpCompanyDashboardsController#show` | `id`, `fund_id` | `show?` | page | refusal partial with the spec message (X9–X12), `:forbidden` |
| `LpCompanyDashboardsController#preview` | `id`, `investor_id`, `fund_id` | `preview?` | page + banner | refusal (X15) |
| (no widget action) | — | — | LP widgets render with the page via `lp_widget_partial` | nothing to fetch (X13) |
| `AggregatePortfolioInvestmentsController#show` (investor role) | `id` (ignores `preview`) | `show?` | redirect to `lp_company_dashboard_path` | refusal (E68, X16) |

**Reviewer checks**
- [ ] Every new action calls `authorize` (`verify_authorized` stays on)
- [ ] `entity_id` is never permitted (DashboardWidgetsController already forces `current_user.entity_id`)
- [ ] `fund_id` on LP routes is always re-checked against the viewer's eligible funds, never trusted

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `LpFolioAllocationQuery.membership` | `SELECT DISTINCT parent_type, parent_id FROM account_entries WHERE ((capital_commitment_id = ? AND fund_formula_id = ?) OR …) AND parent_type IN ('PortfolioInvestment','AggregatePortfolioInvestment') AND deleted_at IS NULL AND reporting_date <= CURDATE() AND ABS(amount_cents) >= 1` | intersect `index_account_entries_on_capital_commitment_id` ∩ `index_account_entries_on_fund_formula_id` | ~2,600 scanned per folio (busiest fund; EXPLAIN est. 283) | one query per request |
| `LpFolioAllocationQuery.own_share` | CTE with `ROW_NUMBER() OVER (PARTITION BY capital_commitment_id, parent_type, parent_id, fund_formula_id ORDER BY reporting_date DESC)` over the same filter (formula ∈ {allocation, fmv}), outer `WHERE rn = 1`. Selects only `capital_commitment_id, parent_type, parent_id, fund_formula_id, amount_cents` | same intersection | ~2× membership | one per fund shown with share |
| PI → API mapping | `PortfolioInvestment.where(id: pi_ids).distinct.pluck(:id, :aggregate_portfolio_investment_id)` | PK | ≤ holdings in fund | — |
| Policy scopes | `where("aggregate_portfolio_investments.fund_id IN (?) OR aggregate_portfolio_investments.id IN (?)", whole_ids, visible_ids)` (with `[0]` for empty lists) | `index_…_on_fund_id`, PK | as today | — |
| `LpLayoutResolver.for` | `DashboardWidget.enabled.where(dashboard_name:, entity_id:).distinct.pluck(:name)` | `index_dashboard_widgets_on_entity_id` | ≤ 10 names | — |
| Settings "used by N companies" | `Investor.where(entity_id:, category: "Portfolio Company", show_to_lps: true).pluck(:id, :tag_list)` then resolver in Ruby | `index_investors_on_entity_id` | ≤ hundreds | — |
| Holdings card | `AggregatePortfolioInvestment.where(id: visible_api_ids, portfolio_company_id:, fund_id:).includes(:investment_instrument)` | `…_on_portfolio_company_id` | ≤ 5 | `includes` (small) |

Resolves design open question 2 (cache): **no cache**, since the one-formula filter keeps it to a few
hundred index rows.

**Reviewer checks**
- [ ] No query on `account_entries` without `capital_commitment_id` in the WHERE clause
- [ ] `distinct.pluck`, never `.pluck.uniq` (CLAUDE.md)
- [ ] No `blank?`/`present?` on any relation, including `visible_*` (use arrays or `exists?`)
- [ ] EXPLAIN on the production copy for `membership` shows the index intersection (attach the output to the PR)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `lp_sharing` | single row update | none | double click (E45) | explicit target value, not a toggle |
| `setup_lp_layout` | create 3 rows in one transaction | none | double submit (E52a) | `exists?` check for an "LP" layout in the transaction. A second submit creates nothing |
| `new_lp_layout` | copy rows in one transaction | none | duplicate layout | refuse if a layout with that normalised name exists |
| Carry-over | single `UPDATE` | — | re-run (E49) | `WHERE show_to_lps = FALSE` |

**Reviewer checks**
- [ ] No email or HTTP call inside any of these transactions (there are none)

---

## Background Jobs

N/A — everything runs inline per request. The carry-over is a migration, not a job.

---

## External Integrations

N/A — no third-party calls. The LP assistant's LLM call is unchanged; only its SQL tool scoping changes.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError` | LP controllers, `lp_sharing` | `rescue_from` in `LpCompanyDashboardsController` → refusal partial; elsewhere the app's standard handler | "You do not have access to this company." (X9–X12) | info log with user, company, fund ids |
| Not shared (switch off) | `LpCompanyDashboardPolicy#show?` returns `:not_shared` via the controller check | controller renders the shared-off partial | "No company information has been shared yet." (E53, X16) | none |
| `ActiveRecord::RecordInvalid` | fund / widget saves | form re-render | validation messages (X1–X6) | none |
| `ArgumentError` (non-LP-safe widget in `LpWidgetData`) | `LpWidgetData.for` | controller → `:forbidden` | empty frame | warn log: entity, widget id (should never happen) |
| `RunQueryTool` missing placeholder | tool | returns the message string to the LLM | assistant retries or says it can't | debug log (existing pattern) |

**Reviewer checks**
- [ ] No bare `rescue => e`
- [ ] Refusal log lines carry `user_id`, `company_id`, `fund_id`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `LpCompanyDashboardPolicy` for every LP route. The PI/API scopes are the single gate for lists. `lp_sharing?` = `update?` plus portfolio-company category |
| Tenant isolation | Eligible funds from `FeederMasterFundAccess.eligible_ids_for_investor`. `company.entity_id == fund.entity_id`. Preview requires `user.entity_id == company.entity_id` and `investor.entity_id == company.entity_id` |
| Data minimisation | LP widgets only via `lp_widget_partial` + `LpWidgetData`, rendered with the page. KPIs filtered to Actual. Valuations limited to the instruments of the LP's visible holdings. Embed Document exposes only one `file_url` |
| Bypass removal | `preview` param ignored for investors. `toggle_show_portfolio` route removed |
| LP-safe boundary | `LP_SAFE_WIDGET_NAMES` enforced by validation (write time) and filtered again at render (read time) |
| Tag injection | Tags only select among the fund manager's own layouts and widgets. The viewer's tags are ignored in LP context (E87) |
| Assistant SQL | Placeholders substituted with integer-cast ids. Queries on portfolio tables without them are rejected (X18) |
| Mass assignment | `entity_id` never permitted. Formula ids validated against the fund (X4, X5) |
| Output | Notices use `t`/plain strings with Rails escaping. Layout names and tags are escaped when shown |

**Reviewer checks**
- [ ] A user from another entity cannot reach any LP page, widget frame, preview or assistant row (X10, C4)
- [ ] An LP cannot reach the internal KPI report or document folder (X14)

---

## Traceability Comments

Required by the user for apply: inline comments name the H/E/X IDs. Format, linking to
`business-rules.md`:

| Where | Comment |
|---|---|
| `LpFolioAllocationQuery.membership` | `# Business rules H2, E10–E21, E28a — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md` |
| `ABS(amount_cents) >= 1` | `# E12/E13 sub-unit ignored, one minor unit counts; E15 negatives count` |
| `reporting_date <= CURDATE()` | `# E17/E18 future-dated ignored, today counts; E20a exited holdings stay visible` |
| `own_share` `ROW_NUMBER()` | `# E29–E33 latest per subject, summed per holding; E38 missing FMV → dash` |
| Scope `resolve` OR condition | `# H1 whole fund unchanged, H2 allocated narrows, E9 hidden, X17 direct request` |
| `LpPortfolioView.apply` | `# E3 hidden keeps the folio/own-share bits so an upload Yes restores the view` |
| `LpLayoutResolver.for` | `# E81 tag layout replaces LP, E83 most matches, E84 tie A→Z, E85 empty skipped, E54 none` |
| Helper LP branch | `# E86 widget tags use company tags only; E87 viewer tags ignored; E54 no catalogue fallback` |
| Validation `lp_safe_in_lp_layout` | `# X6 internal widget refused in an LP layout; E90 only the exact LP token` |
| `LpCompanyDashboardPolicy#show?` | `# X9 not visible, X10 other entity, X11 fund not accessible, X12 hidden view, E53 not shared` |
| Holding show redirect | `# H16 old link redirects; E68 hidden holding refused; X16 preview param ignored` |
| Every Cucumber scenario | `# E12 — Edge case: a sub-unit allocation does not make a holding visible` (one line above each `Scenario:`) |

Every method body also gets step-by-step inline comments (house rule), not just a header comment.

**Reviewer checks**
- [ ] Each significant branch (guard, refusal, skip, fallback, rounding) names its IDs
- [ ] Each feature file header links to `business-rules.md`

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None. Behaviour is opt-in per fund (default view = today's), per company (switch) and per entity (LP layouts) |
| Cron / schedules | None |
| Deploy order | Migrations (widen name → columns → carry-over) → code. Same release |
| Flag bits | Append after `use_own_fx_rates`. Before merge, diff `FundEnabled` flag list against main (the `fund-market-data` change also appends) |
| IN / US | Same code. The carry-over runs per environment on that environment's data |
| Rollback | Code revert. `show_portfolio` is still populated, so the old holding page works again. New columns are harmless if unused. Funds left on Allocated revert to whole-fund behaviour in old code (it reads only `show_portfolios`) |

**Reviewer checks**
- [ ] Deploying with no fund changing its view changes nothing an LP sees, except: holding links redirect, and the 7 Rhapsody/Fireside holdings show on the company page with the same figures
- [ ] Rollback leaves no LP seeing more than before

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `lp_portfolio_view_setting.feature` | — | fund, fund_formula (rule types incl. proforma, company-level, non-portfolio) | `Given fund "GF1" has formulas …`, `When I set the LP portfolio view to "…" with allocation formula "…"` |
| `lp_folio_visibility.feature` | Redis up (fund creation) | capital_commitment, aggregate/portfolio_investment, account_entry (with `parent`, `fund_formula`, `reporting_date`, `amount_cents`) | `Given folio "F-012" has "Allocated Portfolio Cost" ₹2.50 Cr for "Acme Robotics" on "30/09/2026"` |
| `lp_own_share.feature` | — | as above | `Then I should see Your cost "₹2.50 Cr" for "Acme Robotics"` |
| `lp_company_sharing.feature` | — | dashboard_widget (with `name` layouts and `tag_list`), investor with `tag_list` | `Given the LP layout "LP, FinTech" has widgets …` |
| `lp_company_dashboard.feature` | Playwright; an MP4 fixture under `features/support/fixtures/` | document | `When I preview "Acme Robotics" as "Ravi Menon" for "Growth Fund I"` |
| `lp_assistant_portfolio_scope.feature` | Stub the LLM to emit fixed SQL (existing assistant step pattern) | — | `When the LP assistant runs "SELECT … {VISIBLE_API_IDS} …"` |

Runs: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber <file>`, in the background, Redis on 6379, with
pcuc at `-n 4` and a check for concurrent pcuc runs first.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `lp_folio_allocation_warning?` uses `none?`. Visible sets are arrays. Rubocop `IRM/RelationBlankPresent` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | `SELECT DISTINCT` membership. `distinct.pluck` everywhere. Carry-over is one UPDATE |
| Select only needed columns from `account_entries`; no speculative `includes` | Applies | Membership and own share select ≤ 5 narrow columns. No `includes(:account_entries)` |
| Screen dates via `l(...)`; emails `Mon dd, yyyy`; no human-format `strftime` | Applies | "As of" and reporting dates rendered with `l(date)`. No emails |
| Date inputs via `f.date_field` / `date_field_tag`; JS via `locale_date_format.js` | N/A | No date inputs or JS-rendered dates |
| Every query entity-scoped; `authorize` / `policy_scope` on every action | Applies | See Security Review. New actions all `authorize` |
| MCP tool surfaces via ontology YAML | Check | If `list_portfolio_investments`-style MCP tools exist for LPs, they go through the same policy scopes. No ontology change unless a new attribute is exposed. Run `features/ai/mcp_server/mcp_ontology.feature` once |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | Six feature files. No RSpec |
| `bundle exec rubocop` clean incl. `IRM/RelationBlankPresent` | Applies | Run on changed files in each phase |
| Layouts calling `javascript_importmap_tags` render `_locale_date_meta` | N/A | LP page uses existing layouts |
| User guide FAQs (why/how/what-happens) | Applies | Portfolio investments and dashboard widgets guides, linted with UserGuideLint |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | Existing-model changes approved by the user on 2026-10-14 |
