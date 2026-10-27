# Portfolio Report Fund Metrics — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions and ends with
> **Reviewer checks** to tick.

> **Scale to the change.** This change has no schema, controller, job or integration, so those
> sections are `N/A`.

---

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
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- `PortfolioInvestment#as_of` freezes the record it is called on, so every date needs a fresh load. The new helper owns this — see [Method Contracts](#method-contracts).
- `PortfolioInvestment.before` is on-or-before despite its name. "Strictly before the start date" must be `investment_date < start` — see [Queries and Indexes](#queries-and-indexes).
- Percent values are unrounded numbers ×100, or the string "N/A" on a zero base — see [Method Contracts](#method-contracts).
- Dates reach the generators as text from the job; they are coerced once to `Date` — see [Method Contracts](#method-contracts).
- Fund-level ratios use the fund's `XIRR` for `irr`; the company-level `IRR` lookup is left alone — see [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ② Fund figures | `app/packs/funds/funds/models/fund_as_of.rb` | Modified | Money figures as of the date (`committed_amount`, `call_amount`, `collected_amount`, `distribution_amount`, `total_units_premium`, and the tracking ones) |
| ③ Holdings at a date | `app/packs/funds/portfolios/services/portfolio_investments_as_of.rb` | New | Fresh load, batch preload, `as_of` for one PI scope and one date |
| ①④⑤ Consolidated builder | `app/packs/funds/portfolios/services/portfolio_report_consolidated_doc_generator.rb` | Modified | `FundLine`/`FundTotal` `Data.define`; `add_funds`, `fund_totals`, date coercion, fund ratios; header comment updated |
| ⑥⑦ Company builder | `app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb` | Modified | `sold_amount`, `cost_of_remaining` in `add_fund_level_data`; `_vs_budget_compute_percent` in `grid_view_array` |
| Tests | `features/fund/portfolio_report_holdings_at_dates.feature` | New | X1, X2, X3 |
| Tests | `features/fund/fund_as_of_amounts.feature` | New | H18, E27–E31 |
| Tests | `features/fund/portfolio_report_company_fund_lines.feature` | New | H1–H8, E1–E14 |
| Tests | `features/fund/portfolio_report_fund_totals.feature` | New | H9–H13, E15–E22 |
| Tests | `features/fund/portfolio_report_company_fund_data.feature` | New | H14, H15, E23, E24 |
| Tests | `features/fund/portfolio_report_kpi_budget_variance.feature` | New | H16, H17, E25, E26 |
| Tests | `features/step_definitions/portfolio_report_quarter_metrics_steps.rb` | New | Shared setup and assertions |

No change to `KpiDateUtils`, `TemplateDecorator`, `DocGenContext`, models, the job or the Word templates in `public/final_portfolio_report_docs/`.

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] `FundAsOf` users (`capital_remittance_doc_generator`, `capital_distribution_payment_doc_generator`) are unaffected: only new methods are added
- [ ] Files follow the pack layout (`app/packs/funds/portfolios/services`)
- [ ] `KpiDateUtils` (startups pack) is already referenced from other packs, or a boundary check passes

---

## Schema Detail

N/A — no table or column changes; nothing to migrate and no `schema.rb` / `schema_test.rb` edit.

---

## Method Contracts

**`PortfolioInvestmentsAsOf`** (Service, new)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(scope, date)` | `scope`: unloaded `ActiveRecord::Relation` of `PortfolioInvestment`; `date`: `Date` | `Array<PortfolioInvestment>`, each valued and frozen | `ArgumentError` if `scope` is not a relation or `date` is not a `Date` | None (reads only) | Yes; each call loads fresh |

Steps inside: `records = scope.to_a`; buys get `PortfolioInvestment.with_buy_quantities(bought, date:)`; and `PortfolioInvestment.with_net_quantities_on(bought, date)` unless `date == Time.zone.today`; then `records.map { |pi| pi.as_of(date) }`. Same sequence `AggregatePortfolioInvestment#as_of` uses.

**`FundAsOf`** (Model, modified) — new methods, each memoized, returning `Money`

| Method | Rows summed | Currency |
|---|---|---|
| `committed_amount` | `capital_commitments.sum(:committed_amount_cents)` | fund |
| `tracking_committed_amount` | `capital_commitments.sum(:tracking_committed_amount_cents)` | tracking, else fund |
| `call_amount` / `tracking_call_amount` | `capital_remittances.sum(:call_amount_cents)` / `(:tracking_call_amount_cents)` | fund / tracking |
| `collected_amount` / `tracking_collected_amount` | `capital_remittance_payments` of verified remittances `.sum(:amount_cents)` / `(:tracking_amount_cents)` | fund / tracking |
| `distribution_amount` | `capital_distribution_payments.sum(:gross_payable_cents)` | fund |
| `tracking_distribution_amount` | completed `capital_distribution_payments.sum(:tracking_net_payable_cents)` | tracking |
| `total_units_premium` | `fund.fund_units.where(issue_date: ..date).sum(:total_premium_cents)` | fund |
| `target_committed_amount` | the fund's own, not dated | fund |

The fund's own counters roll up the same source columns (`CapitalCommitment`, `CapitalRemittance`, `CapitalRemittancePayment`, `CapitalDistributionPayment`, `FundUnit`), so the sums above agree with them for today (H18). "Verified" is the remittance's `verified` flag as it is now.

**`PortfolioReportConsolidatedDocGenerator`** (Service, modified)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#initialize` | text or `Date` start and end | — | — | Coerces to `Date` once (`Time.zone.parse(x.to_s).to_date`) | Yes |
| `#add_funds(context, investments, fund_ids, ratios)` | as today; reads money from `fund.as_of(@end_date)` | Sets `context[:funds]` to decorated `FundLine`s | — | None | Yes |
| `#fund_totals(company_hashes)` | as today | Decorated `FundTotal`s | — | One `FundRatio` query for all funds | Yes |

**`FundLine`** (`Data.define`, per company in a fund):
`id, name, currency, committed_amount, call_amount, collected_amount, distribution_amount, target_committed_amount, total_units_premium, tracking_committed_amount, tracking_call_amount, tracking_collected_amount, tracking_distribution_amount, cost_of_investment, cost_of_investment_prior, cost_of_investment_between, cost_of_remaining, cost_of_remaining_prior, cost_of_sold_between, fmv, fmv_prior, fmv_change_percent, fmv_fy_start, fmv_fy_start_change_percent, irr, moic, ratios`

**`FundTotal`** (`Data.define`, per fund):
`name, currency, committed_amount, call_amount, collected_amount, distribution_amount, target_committed_amount, total_units_premium, tracking_committed_amount, tracking_call_amount, tracking_collected_amount, tracking_distribution_amount, collected_percent, uncollected_amount, uncollected_percent, company_count, cost_of_investment, cost_of_investment_prior, cost_of_investment_between, cost_of_remaining, cost_of_remaining_prior, cost_of_sold_between, fmv, fmv_prior, fmv_change_percent, irr, moic, tvpi, dpi, rvpi, custom_fields`

`Ratio = Data.define(:name, :value)` replaces the `OpenStruct` rows in `ratios`. `custom_fields` stays an `OpenStruct` (keys are form-field names).

**Value rules**

| Value | Rule |
|---|---|
| Money | `Money.new(cents, fund.currency)`; fund money and tracking figures come from `fund.as_of(@end_date)` (the `Fund#as_of` factory already exists), the target committed amount from the fund |
| `cost_of_investment`, `_prior`, `_between` | Sum of `amount_cents` of buys (`quantity` positive) from the end-date set, split on `investment_date < start` and `start..end` |
| `cost_of_sold_between` | Sum of `cost_of_sold_cents` of sells with `investment_date` in `start..end`, negated to positive |
| `cost_of_remaining` | Sum of `cost_of_remaining_cents` over the end-date set (zero for sells) |
| `cost_of_remaining_prior`, `fmv_prior` | Prior set (`investment_date < start`) valued at `start − 1` |
| `fmv_fy_start` | PIs with `investment_date < fy_start` valued at `fy_start − 1`; reuses the prior result when the days are equal |
| Percent | `(current − base) / base × 100` with `BigDecimal`; "N/A" when base is zero; not rounded (template formats) |
| `collected_percent` | `collected / committed × 100`; "N/A" when committed is zero |
| `company_count` | Number of lines for the fund |
| `fy_start` | `KpiDateUtils.fiscal_year_start(end, KpiDateUtils.resolve_fiscal_year_start_month(fund, fund.entity_id))` |

**`PortfolioReportDocGenerator`** (Service, modified)

| Method | Change |
|---|---|
| `#add_fund_level_data` | Value via `PortfolioInvestmentsAsOf`; the struct gains `sold_amount` (sum of sells' `amount_cents`, positive) and `cost_of_remaining`; existing fields unchanged. The struct stays an `OpenStruct` (two fields are added; the `Data.define` shapes are the consolidated report's) |
| `#grid_view_array` | In the `COMPARATOR_TAGS` loop, also set `"#{label}_vs_#{tag.downcase}_compute_percent"` |
| new private `#variance_of(kpi, comparator)` | `(kpi.value − comparator.value) / comparator.value × 100`; "N/A" when either is nil or comparator value is zero |

**Reviewer checks**
- [ ] No caller passes loaded PIs to the helper; the only way in is a relation
- [ ] The prior set uses `<` start, the end set `<=` end; neither uses `PortfolioInvestment.before`
- [ ] `cost_of_investment`'s meaning is unchanged for every existing reader
- [ ] Every `Data.define` is built with all keys; a missing key fails loudly

---

## Controllers, Params and Responses

N/A — no controller action is added or changed.

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `#company_data` (existing) | company PIs `investment_date <= end` | `portfolio_company_id`, `investment_date` | tens | unchanged |
| `#add_funds`, end set | `investments.where(fund_id:)` | existing PI indexes | tens per fund | helper batches sold/transfer and net quantities (2 + 2 grouped queries) |
| `#add_funds`, prior set | `investments.where(fund_id:).where(investment_date: ...start)` | same | ≤ end set | same batching |
| `#add_funds`, FY set | `... where(investment_date: ...fy_start)`; skipped when `fy_day == prior_day` | same | ≤ prior set | same batching |
| `#add_funds`, fund money | `FundAsOf` sums over commitments, remittances, remittance payments, distribution payments, fund units | existing indexes on `fund_id` and the date columns | ≤ thousands per fund | one `FundAsOf` per fund per generator run, memoized in the generator |
| `#fund_totals`, ratios | `FundRatio.default.where(owner_type: "Fund", owner_id: fund_ids, name: %w[XIRR MOIC TVPI DPI RVPI], computation_context_id: nil, end_date: ..end, entity_id: entity_ids).order(end_date: :desc, id: :desc)`, first per `[fund, name]` | `fund_ratios` fund/owner indexes | ≤ funds × 5 × runs | one query for all funds |

- `PriceResolver.lookup` still runs once per buy per date inside `as_of`; it is not batched today and this change does not batch it.
- Dedup of the latest ratio is done in Ruby over the ordered result, as the existing company ratio lookup does.

**Reviewer checks**
- [ ] Every query is scoped by the selected companies' PIs or by `entity_id`
- [ ] No N+1 on ratios (one query per run, not per fund)
- [ ] The FY set is skipped when its day equals the prior day

---

## Transactions, Locking and Concurrency

N/A — read-only; no writes, locks or shared state.

---

## Background Jobs

N/A — no job or cron added. `PortfolioReportJob` calls the generators as before.

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ArgumentError` (non-relation or non-`Date`) | `PortfolioInvestmentsAsOf.call` | Programming error; not rescued | The run fails and surfaces through the existing job error report | Existing job error handling |
| Zero base in a percent | generators | Returns "N/A" | "N/A" in the document | Not logged |
| Fund ratio missing | `#fund_totals` | Returns "N/A" | "N/A" | Not logged |

- A one-line `Rails.logger.debug` per fund line names fund id, company id and the three days.

**Reviewer checks**
- [ ] No bare `rescue`; "N/A" comes from an explicit zero or nil check

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged: the caller already restricts the companies the user may report on |
| Tenant isolation | Funds are those of the selected companies' PIs; the ratio query also filters `entity_id` |
| Secrets | N/A |
| Input / output sanitisation | Numbers only; names go through the existing Sablon rendering |
| Mass assignment | N/A |

**Reviewer checks**
- [ ] A company from another entity cannot appear in the totals through the ratio query

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None. Financial-year default uses the existing `CURRENT_SITE` rule inside `EntitySetting.geo_default_month_offset_for_fy` |
| Feature flag | None; unused fields have no effect |
| Cron / schedules | None |
| Deploy order | Code, then ship the updated Word templates |
| Rollback | Revert the code; older templates ignore the new fields |

**Reviewer checks**
- [ ] Safe to deploy before the new templates and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `fund_as_of_amounts.feature` | Fund with commitments, a call, remittances, payments (verified and not), distribution payments and fund units, dated before and after 30-Sep | existing capital commitment, call, remittance, payment and distribution factories | `Then the fund as of <date> shows <figure> <value>` |
| `portfolio_report_holdings_at_dates.feature` | Valuations for A and B at 31-Mar, 30-Jun, 30-Sep | fund, investor, investment instrument, portfolio investment, valuation, entity setting | `Given the quarter report data of the Inflexor example`, `Given the fund's financial year starts in <month>`, `When the consolidated report data is built` |
| `portfolio_report_company_fund_lines.feature` | Same | same | `Then the line for "<company>" shows <field> <value>` (compares percent to one decimal) |
| `portfolio_report_fund_totals.feature` | Same + fund ratios | `fund_ratio` | `Given the fund has ratio "<name>" of <value> on <date>`, `Then the fund total shows <field> <value>` |
| `portfolio_report_company_fund_data.feature` | Same | same | `When the company report data is built`, `Then the fund data shows <field> <value>` |
| `portfolio_report_kpi_budget_variance.feature` | Existing KPI steps | existing | Reuse "the report row ... should have ... equal to" |

- Generators are driven through their data-building steps and read the context hash they pass to Sablon, not the rendered Word file; one scenario (E14) renders a template.
- Redis must be up on 6379; every run uses a fresh `TEST_ENV_NUMBER`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | New code checks arrays and uses `exists?` where a relation is tested |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | Helper batches quantities; funds come from `pluck(:fund_id).uniq` as today |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No account entries |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | N/A | No screen or email date; the document dates already exist |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No input |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | No action; queries scoped as in Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP surface changes |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | All tests are features |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run on the modified files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
