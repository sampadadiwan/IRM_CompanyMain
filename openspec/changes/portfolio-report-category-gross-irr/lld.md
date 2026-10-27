# Portfolio Report Category and Gross Portfolio IRR — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Small change.** Two edits in two existing files, plus tests. Sections that do not apply keep
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

- `gross_portfolio_irr` is added to `FundTotal` and to `FUND_RETURN_RATIOS` only. `fund_total` already builds every return from `FUND_RETURN_RATIOS`, so its body does not change. See [Method Contracts](#method-contracts).
- `FundTotal` is a `Data.define`: the new member is required at construction, so a forgotten member fails loudly. See [Method Contracts](#method-contracts).
- `fund_returns` loads every stored run (not only the latest) of each ratio name up to the end date, then keeps the newest per fund and name in Ruby. One more name means one more ratio's runs are loaded and discarded: 5 names today, 6 after, about 20% more rows. Existing behaviour, accepted. See [Queries and Indexes](#queries-and-indexes).
- `category` is a fixed row key set from `ikm.category.to_s`, not lowercased. See [Method Contracts](#method-contracts).
- `FundLine`, `add_fund_level_data` and the Sablon word service are deliberately untouched. See [File Map](#file-map).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ②, `grid_view_array` | `app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb` | Modified | Add `"category" => ikm.category.to_s` to `row_data`, beside `data_type`; extend its comment |
| ④, ⑤ | `app/packs/funds/portfolios/services/portfolio_report_consolidated_doc_generator.rb` | Modified | Add `:gross_portfolio_irr` to `FundTotal` (beside `:irr`) and `gross_portfolio_irr: "Gross Portfolio IRR"` to `FUND_RETURN_RATIOS`; update the header comment's list of returns |
| Tests | `features/fund/portfolio_report_kpi_category.feature` | New | H1–H3, E1, E2 |
| Tests | `features/fund/portfolio_report_fund_total_gross_irr.feature` | New | H4–H7, E3–E11 |
| Tests | `features/step_definitions/portfolio_report_category_gross_irr_steps.rb` | New | The few steps listed in Test Plumbing |

Not modified, on purpose: `FundLine`, `add_fund_level_data`, `fund_ratio_values` (company-level), `portfolio_report_sablon_word_service.rb`, `public/final_portfolio_report_docs/*`.

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] Neither new feature file nor the step file exists yet (a Write over an existing file is silent)

---

## Schema Detail

N/A — no table, column or index changes.

---

## Method Contracts

**`PortfolioReportDocGenerator`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `grid_view_array` (private) | `portfolio_company`, `end_date`, `category: nil` | Array of `OpenStruct` rows; each gains `"category"` (String, `""` when nil, case kept) | None new | None | Yes |

**`PortfolioReportConsolidatedDocGenerator`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `fund_returns` (private) | `fund_ids` | Hash `[fund_id, ratio name] => value`, now including "Gross Portfolio IRR" | None new | None | Yes |
| `fund_total` (private) | `funds`, `returns`, `custom_fields` | `FundTotal` with `gross_portfolio_irr` (value or `"N/A"`) | `ArgumentError` if the `Data` member were missing | None | Yes |

**Reviewer checks**
- [ ] `FundTotal` and `FUND_RETURN_RATIOS` have the same new member name, `gross_portfolio_irr`, and `fund_total` still passes it through `**FUND_RETURN_RATIOS.keys.index_with`
- [ ] The row key is the string `"category"` like `"header"` and `"data_type"`, and no period label can equal it
- [ ] No other `FundTotal.new` call exists (a second constructor would need the member)

---

## Controllers, Params and Responses

N/A — no controller action is added or changed.

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `fund_returns` | `FundRatio.default.where(owner_type: "Fund", owner_id: fund_ids, name: FUND_RETURN_RATIOS.values, computation_context_id: nil, end_date: ..end, entity_id: ...)` ordered `end_date desc, id desc`, `pluck` | `index_fund_ratios_on_owner` (`owner_type`, `owner_id`) | Funds x names x runs up to the end date; one more name adds that name's runs | One query for all funds, already; unchanged |
| `grid_view_array` | None new | n/a | n/a | Mapping already loaded |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`: `fund_returns` keeps its `entity_id:` filter
- [ ] No N+1 and no new query
- [ ] Accepted: the query returns every stored run of each ratio name up to the end date, one row per run, and Ruby keeps only the newest per fund and name. Each fund ratio run stores one row per ratio, so a fund run monthly for 3 years has about 36 rows per name; with 5 names today that is about 180 rows per fund, and Gross Portfolio IRR makes it about 216 (+20%). A fund run daily would be about 1,100 rows per name. Small at current volumes; moving "latest per fund" into SQL would be a separate change for all returns together

---

## Transactions, Locking and Concurrency

N/A — read-only; nothing is written.

---

## Background Jobs

N/A — no job is added or changed. The existing report job calls the builders.

---

## External Integrations

N/A — no third-party call.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| None new | n/a | n/a | n/a | n/a |

An absent run reads as `"N/A"` (`returns.fetch(key, "N/A")`) and an absent category as `""`; neither raises.

**Reviewer checks**
- [ ] No `rescue` added
- [ ] A run stored with a nil value behaves exactly as XIRR does (shared lookup), and this is accepted: see the design's Risks

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | No new entry point; the report job's existing authorization applies |
| Tenant isolation | `fund_returns` keeps its `entity_id` filter on the companies' entities |
| Secrets | None |
| Input / output sanitisation | `category` is a stored label rendered by the template engine as text, like `header` |
| Mass assignment | None |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool: no route, job or tool is added

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None; unused fields are ignored by templates |
| Cron / schedules | None |
| Deploy order | Code only. Template authors add the merge fields afterwards |
| Rollback | Revert the code. A template that already uses a new field would then fail to fill it, so revert templates first or accept that |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/fund/portfolio_report_kpi_category.feature` | Background as `portfolio_report_kpi_vs_budget.feature` (company admin, portfolio company "MyFavStartup") | Existing KPI mapping and KPI report setup steps | `Given the {string} KPI mapping has category {string}` (updates the mapping, `""` clears it); `When the portfolio report rows for the {string} category are built up to {string}` (calls `grid_view_array(..., category:)`); `Then the report row {string} should have category {string}`; `Then the report has no row {string}` (the category's list holds only its own rows) |
| `features/fund/portfolio_report_fund_total_gross_irr.feature` | Background as `portfolio_report_fund_totals.feature` (`the Inflexor quarter data`) | `:fund_ratio` via the existing `the fund has a {string} ratio of {float} on {string}` (and `... in the scenario {string}`) | `Given the fund {string} has a {string} ratio of {float} on {string}` (a ratio of the second fund, for H6); `Given {string} has an IRR of {float} in the Inflexor fund on {string}` (the company's own IRR, owner is the company, for H7); `Then the total of {string} shows {word} {string} as a number` (the plain `shows` step reads "N/A" as 0, so E8's zero needs this strict check); `Then the line of {string} has no {word} field` (the `FundLine` does not respond to the field) |

Reused as they are: `the portfolio report rows are built up to {string}`, `the consolidated report data is built for {string} to {string}`, `the total of {string} shows {word} {string}` (reads any `FundTotal` field and accepts "N/A"), `the line of {string} shows {word} {string}`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | No relation tested |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | N/A | No new bulk operation |
| Select only needed columns when loading many `account_entries` | N/A | `account_entries` not read |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | N/A | No date formatting added |
| Date inputs use `f.date_field` / `date_field_tag` | N/A | No input |
| Every query entity-scoped; Pundit on every action | Applies | `fund_returns` keeps its `entity_id` filter; no action added |
| MCP tool surfaces changed only via the ontology YAML | N/A | No tool surface changes |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Two feature files; every run prefixed |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run on the two modified files and the step file |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
