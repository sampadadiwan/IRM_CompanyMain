# Portfolio Report Quarter Activity and KPI Change Direction — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Small change.** Edits in five existing files, plus tests. Sections that do not apply keep
> their heading with `N/A — <reason>`.

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

- `add_fund_level_data` stops ignoring its start date (`_start_date` becomes `start_date`) and adds four keys to the fund struct, from the frozen list it already builds. No new query. See [Method Contracts](#method-contracts).
- The start date can reach the generator as text (the consolidated generator's X2 case), so it is converted with `to_date` before it is compared. A text date compared with a `Date` raises.
- `Kpi.change_against` divides by `comparator.value.abs`, for a percentage KPI as for any other (the KPI's data type is not read). `year_over_year_change`, with its 9,999.99 limit, needs no edit. `variance_of` calls `Kpi.change_against` instead of repeating the formula. `change_percent` in the consolidated generator gets the same `abs`.
- `KpiPercentageChangeJob` preloads `:investor_kpi_mapping` beside `:kpi_report`, so reading the data type adds no query per KPI.
- The consolidated `fund_line` values the earlier holdings at the end date's value per unit (one lookup per instrument) into two new fields, `fmv_at_prior_quantity` and `fmv_at_fy_start_quantity`, and `fmv_change_percent` and `fmv_fy_start_change_percent` are worked from them. `fmv`, `fmv_prior` and `fmv_fy_start` are untouched. `FundTotal` gets `fmv_at_prior_quantity` as a sum.
- `percent_of` and `kpi_percentage_class` are not edited: the colours read the stored change and follow its sign.
- Stored `percentage_change` values only change when `KpiPercentageChangeJob` runs; no migration. See [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ③, ④ | `app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb` | Modified | `add_fund_level_data`: take `start_date`, split period buys and sales, add `buy_pis_present`, `sell_pis_present`, `cost_of_investment_between`, `cost_of_sold_between` to the struct; `variance_of` calls `Kpi.change_against` |
| ⑥ | `app/packs/startups/kpis/models/kpi.rb` | Modified | `change_against` divides by `comparator.value.abs`; update its comment |
| ⑤ | `app/packs/startups/kpis/jobs/kpi_percentage_change_job.rb` | Modified | Add `:investor_kpi_mapping` to the `preload` of the recompute's query |
| ⑥, ⑦ | `app/packs/funds/portfolios/services/portfolio_report_consolidated_doc_generator.rb` | Modified | `change_percent` divides by `base.to_d.abs`; `FundLine` gains `fmv_at_prior_quantity`, `fmv_at_fy_start_quantity`; `FundTotal` and `FUND_LINE_SUMS` gain `fmv_at_prior_quantity`; `fund_line` fills them and works both percents from them; `fund_total` works its percent from the sums; two small private helpers (below) |
| Tests | `features/fund/portfolio_report_company_quarter_activity.feature` | New | H1–H6, E1–E10, X1 |
| Tests | `features/startup/kpi_change_direction.feature` | New | H7–H14, E11–E16, E22–E24, E33 |
| Tests | `features/fund/portfolio_report_change_direction.feature` | New | H15–H18, E17–E21 |
| Tests | `features/fund/portfolio_report_fmv_per_unit_change.feature` | New | H19–H24, E25–E32 |
| Tests | `features/step_definitions/portfolio_report_quarter_change_steps.rb` | New | The few steps in Test Plumbing |

Not modified, on purpose: `percent_of`, `year_over_year_change`, `PERCENTAGE_CHANGE_LIMIT`, `kpis_helper.rb`, `fmv`, `fmv_prior` and `fmv_fy_start` and their formulas, `PortfolioInvestmentsAsOf`, `PriceResolver`, the Sablon word service, `public/final_portfolio_report_docs/*`.

**Reviewer checks**
- [ ] Every box in the design's picture has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] None of the three new feature files nor the step file exists yet (a Write over an existing file is silent)
- [ ] `features/fund/portfolio_report_company_fund_data.feature`, `features/fund/portfolio_report_fund_totals.feature`, `features/fund/portfolio_report_company_fund_lines.feature` and `features/startup/kpi_ytd_yoy_percentage_change.feature` are only re-run, not edited (their fair market value change cases keep their values when no units change)

---

## Schema Detail

N/A — no table, column or index changes. `percentage_change` stays decimal(6,2).

---

## Method Contracts

**`PortfolioReportDocGenerator`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `add_fund_level_data` (private) | `context`, `portfolio_company`, `start_date` (Date or text), `end_date` | Stores `<fund>_data` and `<fund>_latest_pi` in `context`; the struct gains the four quarter keys | None new | None | Yes |
| `variance_of` (private) | `kpi`, `comparator` | BigDecimal, or "N/A" when either figure is missing or the change is nil | None new | None | Yes |

**`Kpi`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `change_against` (class) | `comparator`, `kpi` | `(kpi.value - comparator.value) / comparator.value.abs * 100` for every KPI, nil when the comparator is zero | None new | None | Yes |

**`PortfolioReportConsolidatedDocGenerator`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `change_percent` (private) | `current`, `base` | `(current - base) / base.abs * 100` or "N/A" when the base is zero | None new | None | Yes |
| `unit_values_at_end` (private, new) | `pis` (a frozen list), `fund` | Hash `investment_instrument_id => value per unit in fund currency at @end_date`; one `pi.latest_valuation_on(@end_date)&.per_share_value_in(fund.currency, @end_date, fund:)` per instrument (first PI of each instrument), 0 when there is no valuation | None new | None | Yes |
| `value_at_unit_values` (private, new) | `pis` (a frozen list), `unit_values` | Money in the fund's currency: sum over the buys of `net_quantity * unit_values[instrument_id]`, rounded to cents | None new | None | Yes |

Quarter keys, built from the frozen list `fund_pis` (the same Enumerable list as `buys` and `sells` already use):

| Key | Definition |
|---|---|
| `buy_pis_present` | `period_buys.any?`, where period buys are `buys` with `investment_date >= start_date` |
| `cost_of_investment_between` | `Money.new(period_buys.sum(&:amount_cents), fund.currency)` |
| `sell_pis_present` | `period_sells.any?`, where period sells are `sells` with `investment_date >= start_date` |
| `cost_of_sold_between` | `Money.new(period_sells.sum { \|pi\| pi.cost_of_sold_cents.abs }, fund.currency)`, as the consolidated line does |

`fund_line` after the change (the existing lists, no new load):

| Field | Definition |
|---|---|
| `fmv_at_prior_quantity` | `value_at_unit_values(prior_pis, unit_values)` where `unit_values = unit_values_at_end(prior_pis + fy_pis, fund)` (an instrument held at either date is looked up once) |
| `fmv_at_fy_start_quantity` | `value_at_unit_values(fy_pis, unit_values)` |
| `fmv_change_percent` | `change_percent(fmv_at_prior_quantity.cents, fmv_prior.cents)` |
| `fmv_fy_start_change_percent` | `change_percent(fmv_at_fy_start_quantity.cents, fmv_fy_start.cents)` |

`fund_total`: `fmv_at_prior_quantity` is summed by `FUND_LINE_SUMS` and `fmv_change_percent` is `change_percent(sums[:fmv_at_prior_quantity].cents, sums[:fmv_prior].cents)`.

**Reviewer checks**
- [ ] `net_quantity` of a frozen buy is the quantity held at the date its list was valued (`compute_buy_metrics` calls `set_buy_quantities(date)` first); the spike scenario H19 proves it before the percent relies on it
- [ ] Sells in `prior_pis` and `fy_pis` are skipped by `value_at_unit_values` (they carry no `fmv`); only buys count
- [ ] `fmv`, `fmv_prior` and `fmv_fy_start` code is unchanged
- [ ] `FundTotal` has no `fmv_at_fy_start_quantity` (it has no FY percent today)
- [ ] The key names equal the consolidated `FundLine` members (`cost_of_investment_between`, `cost_of_sold_between`)
- [ ] `buy_pis_present` and `sell_pis_present` are `true` or `false`, never nil (`any?`)
- [ ] The start date is converted once with `to_date` at the top of the method; the end date already is where it is used
- [ ] `change_against` keeps its `return nil if comparator.value.zero?` guard before the division
- [ ] No other caller of `change_against` exists besides `recompute_percentage_change` and `year_over_year_change` (checked: none)
- [ ] `variance_of` still returns "N/A" for a nil KPI, a nil comparator and (money or numeric KPI) a zero comparator
- [ ] A KPI without a mapping is treated as money or numeric

---

## Controllers, Params and Responses

N/A — no controller action is added or changed.

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `add_fund_level_data` | None new; filters the in-memory list | n/a | One list per fund | Already loaded |
| `fund_line` (price at the end date) | `PriceResolver.lookup` through `latest_valuation_on`, once per instrument held at an earlier date; plus the currency conversion `per_share_value_in` (rate lookup) | Existing valuation and rate indexes | One per instrument | Instrument ids taken from the lists in memory |
| `KpiPercentageChangeJob` | Existing: approved KPIs of a company joined to the report | Existing | Every approved KPI of the company | `preload(:kpi_report, :investor_kpi_mapping)`, so the data type read in `change_against` adds no query per KPI |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`: the job keeps its `entity_id` and policy scope
- [ ] No N+1 and no new query

---

## Transactions, Locking and Concurrency

N/A — the report is read-only. The recompute saves each row as it does today (`kpi.save` per row); a double run gives the same result.

---

## Background Jobs

| Job | Queue | Trigger | Retry / idempotency |
|---|---|---|---|
| `KpiPercentageChangeJob` (existing, unchanged) | low | "Recompute percentage change" on a KPI report, or after an approval or cumulation that asks for it | A rerun recomputes the same values |

The code change makes the job write the corrected sign. It does not run it.

---

## External Integrations

N/A — no third-party call.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| None new | n/a | n/a | n/a | n/a |

A zero or missing comparison figure is nil or "N/A" as before. A text start date is converted, not rejected; a date that cannot be parsed would raise as it would for the end date.

**Reviewer checks**
- [ ] No `rescue` added
- [ ] `to_date` is called on the start date, not `Date.parse` (it accepts a Date and text alike)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | No new entry point; the report job and the recompute action keep their authorization |
| Tenant isolation | Investments and KPIs are already scoped to the company and entity |
| Secrets | None |
| Input / output sanitisation | The new fields are numbers and booleans |
| Mass assignment | None |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool: none is added

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None; unused fields are ignored by templates |
| Cron / schedules | None |
| Deploy order | 1 Deploy the code. 2 Run "Recompute percentage change" for each company that has a negative KPI figure. 3 Generate reports. Template authors add the quarter fields at any time after step 1 |
| Rollback | Revert the code. Stored changes that were already recomputed keep the corrected sign until the recompute is run again on the old code; a template that uses a quarter field would fail to fill it, so revert templates first or accept that |

**Reviewer checks**
- [ ] Safe to deploy with the fields unused
- [ ] The rollout order is in the QA checklist and the tasks

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/portfolio_report_company_quarter_activity.feature` | Background as `portfolio_report_company_fund_data.feature` (Meera, company admin, the Inflexor quarter data) | Reuses `the Inflexor quarter data` and `{string} sells {int} crore of shares on {string}` | `Given {string} buys {int} crore of shares on {string}` (a further buy through `fund_metrics_investment`); `Given {string} buys {int} crore of shares in the second fund on {string}` (a buy in a second fund); `Given {string} sold everything before {string}` (E10); `When the company report data is built for the text dates {string} to {string}` (X1, passes text, not `Date`); `Then the fund data of {string} shows {word} {string}` (booleans); `Then the fund data of {string} shows {word} {string} crore` is reused for amounts |
| `features/startup/kpi_change_direction.feature` | Background as `kpi_ytd_yoy_percentage_change.feature` | `the following Monthly KPI Reports exist with KPIs:` | None for the KPI steps: `the KPI percentage change job runs`, `the {string} KPI {string} for {string} should have a percentage change of {float}`, `... should have an empty percentage change`, `the {string} KPI {string} for {string} has a stored percentage change of {float}` and `the {string} KPI mapping has a lower threshold of {int}` are reused; E15 reads the grid colour class with the existing "should show ... with no colour" helper, plus one step `Then the {string} KPI {string} for {string} should show in red in the grid` |
| `features/fund/portfolio_report_change_direction.feature` | Background as `portfolio_report_kpi_budget_variance.feature` | Same KPI report table step; `the {string} KPI mapping has data type {string}` (existing) for the percentage KPI | `When the fair market value change is worked out from {float} to {float}` (calls the private `change_percent` on an allocated consolidated generator, as the existing steps do); `Then the fair market value change is {float}` / `... is {string}` |
| `features/fund/portfolio_report_fmv_per_unit_change.feature` | Background as `portfolio_report_fund_totals.feature` (a logged-in user, a fund) with its own small data, not the Inflexor crore data | `:investment_instrument`, `:valuation` factories through `fund_metrics_investment` and `fund_metrics_valuation` (existing helpers) | `Given {string} holds {int} units in the fund on {string}` and `... buys {int} more units on {string}` / `... sells {int} units on {string}`; `Given {string} has a value per unit of {int} on {string}`; `Given {string} has a second instrument ...` for H21; `Given the fund and instrument currencies differ ...` for E29; `When the consolidated report data is built for {string} to {string}` (existing); `Then the line of {string} shows {word} {string}` and `Then the total of {string} shows {word} {string}` (existing, read the percent and amounts) |

Reused as they are: `the portfolio report rows are built up to {string}`, `the report row {string} should have {string} equal to {string}`, `the company report data is built for {string} to {string}`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | No relation tested; the list is an Array and uses `any?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | N/A | No new bulk operation |
| Select only needed columns when loading many `account_entries` | N/A | `account_entries` not read |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | N/A | No date formatting added |
| Date inputs use `f.date_field` / `date_field_tag` | N/A | No input |
| Every query entity-scoped; Pundit on every action | Applies | Nothing new; existing scopes kept |
| MCP tool surfaces changed only via the ontology YAML | N/A | The AI assistant's data manager only reads the stored change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Three feature files; every run prefixed |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run on the three modified files and the step file |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
