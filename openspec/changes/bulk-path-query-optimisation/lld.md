# Faster bulk jobs — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Business rules](business-rules.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.**

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
- [Project rules checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

| Decision | Value |
|---|---|
| Batch size | 1,000 (`find_each` default) everywhere |
| New lookups' lifetime | one job `perform` / one method call; no class-level or thread-level state |
| Signature changes | additive optional kwargs only; existing callers unchanged |
| New tables / indexes | none |
| Behaviour changes | D3 (KPI repeat skip), D4 (portfolio import aggregate save) — approved 2026-10-22 |

**Reviewer checks**
- [ ] No `CurrentAttributes`, `RequestStore`, class variable or `Thread.current` added
- [ ] Every new kwarg defaults to today's behaviour

## File Map

| File | Change |
|---|---|
| `app/packs/funds/capital_calls/jobs/capital_call_job.rb` | re-save loop → `includes(...).find_each`; `Fund.no_touching` around `generate_remittance_payments`; single fund touch after |
| `app/packs/funds/capital_remittances/models/capital_remittance_payment.rb` | `unverify_remittance`: Preloader after `reload` |
| `app/packs/funds/capital_remittances/models/concerns/capital_remittance_fees.rb` | `setup_call_fees`: `pluck` 3 columns |
| `app/packs/funds/capital_remittances/services/import_capital_remittance.rb` | pass `entity:` object |
| `app/packs/startups/kpis/jobs/kpi_cumulate_job.rb` | `preload(:investor_kpi_mapping)`; D3 `seen` Set |
| `app/packs/startups/kpis/models/concerns/kpi_cumulative.rb` | `process_cumulative_kpi(..., lookup: nil)`; build/consult/add-back |
| `app/packs/startups/kpis/models/kpi.rb` | cascade sibling query `preload(:investor_kpi_mapping)` |
| `app/packs/startups/kpis/services/kpi_workbook_reader.rb` | per-report KPI maps beside `@results`; assign entity |
| `app/packs/funds/funds/services/import_fund_formula.rb` | `@max_seq`; `FundFormula.acts_as_list_no_update` when k > `@max_seq` |
| `app/packs/funds/portfolios/models/concerns/portfolio_computations.rb` | `set_buy_quantities(quantities: nil)` |
| `app/packs/funds/portfolios/models/aggregate_portfolio_investment.rb` | `as_of` computes `net_quantity_on` parts once |
| `app/packs/funds/portfolios/models/portfolio_investment.rb` | `compute_avg_cost`: skip aggregate save when counters skipped (D4) |
| re-value jobs (5 files) + `ImportPortfolioInvestment` | build grouped sums per batch, pass `quantities:` |
| `features/step_definitions/query_budget_steps.rb` (new) | query-counting steps |
| `features/fund/bulk_query_*.feature`, `features/startup/bulk_query_*.feature` (new) | one per phase |

**Reviewer checks**
- [ ] No existing `.feature` or step-definition file in this list

## Review follow-ups (2026-10-22)

| Finding | Decision |
|---|---|
| Cumulation lookup period compared case-sensitively | key `[period.downcase, as_of]` (MySQL collation) |
| Cumulation held KPI objects (stale `rag_status` after the cascade) | lookup holds reports only (X4) |
| KpiApproveAllJob: 25 Sidekiq retries re-alert on a permanent error | `sidekiq_options retry: false`; `ActiveRecord::Deadlocked` re-raised without an alert so `retry_on` handles it |
| DealingPricer preloaded fills without what `evergreen_dealing_helper` reads | `dealing_fills: [:dealing_date, :fund_nav, :capital_distribution_payment]` |
| CapitalCallJob touched the fund on every run | touch only if a remittance was created, a payment created, or a re-save changed something (H8) |
| D4 lost the aggregate save's failure signal | step returns `aggregate.reload.valid?` — the only way that save could fail |

**Reviewer checks**
- [ ] Each follow-up has its scenario or a stated reason it can't be tested on SQLite (period case)

## Schema Detail

N/A — no schema change.

## Method Contracts

| Method | Signature change | Contract |
|---|---|---|
| `KpiCumulative#process_cumulative_kpi` | none — **as built (revised after review, 2026-10-22):** the lookup holds the target **reports only**, keyed `[period.downcase, as_of]` (MySQL compares `period` case-insensitively; stored periods are mixed case). The approved KPI is still found fresh per target: a held KPI object kept a stale `rag_status` after the RAG cascade rewrote it via `update_column`, so its own `recompute_rag_status!` could skip a needed write (X4). Originally: `perform_cumulation` / `perform_forward_fill` wrap their body in `with_cumulation_lookup`, which sets `@cumulation_lookup` for that one call and clears it in `ensure` (same lifetime as a kwarg, no change to the ten callers) | `lookup = {reports: {[period, as_of] => KpiReport}, kpis: {kpi_report_id => Kpi}}`; nil → today's queries; caller adds back nothing — method writes created rows into `lookup` |
| `KpiWorkbookReader#save_kpi_entry` | internal | consults `@kpi_maps[report.id]`; writes a newly saved KPI back under `[name.downcase, mapping_id]` — **downcased** because the MySQL collation of the replaced queries is case-insensitive (SQLite tests can't show this); a failed save restores the stored values |
| `PortfolioComputations#set_buy_quantities` | none — **as built:** `PortfolioInvestment.with_buy_quantities(records)` / `.find_each_with_buy_quantities(scope)` set a one-shot `preloaded_buy_quantities` `{date:, sold:, transfer:}` on each record; `set_buy_quantities(date)` uses it only for the same date (else sums live) and clears it. Used by the 7 PortfolioInvestmentUpdate loops |
| `PortfolioInvestment.with_net_quantities_on(records, date)` (phase 8) | new class method | sets a one-shot `preloaded_net_quantity_on` `{date:, sold:, transfer:}` per record; `sold` sums attributions joined to their sold PI with `include_proforma.before(date)` merged — the live `net_quantity_on` rows, which in fact leave proforma sales out (the join's ON clause keeps the default `proforma = FALSE`; E13) and so differ from `set_buy_quantities`' sold; `converted` is keyed by `[pi_id, fund_id]` because the live sum is `fund.stock_conversions`; `net_quantity_on(date)` uses it only for that date, else sums live |
| `CapitalCallJob#create_remittances` (phase 8) | internal | `entity.form_types.where(name: "CapitalRemittance").last` once per run, passed as `form_type:`; `setup_form_type`'s `||=` then skips; nil → per-record lookup as today |
| `AggregatePortfolioInvestment#net_quantity_on` | `+ parts: nil` | `net_quantity_parts(end_date)` read once in `as_of` and handed to `fmv_on_date` and the bought-only call; nil → today's queries; nothing cached on the object |
| `PortfolioInvestmentAction#compute_avg_cost` (step) | `+ skip_aggregate_save: false` | D4: `ImportPortfolioInvestment` passes true; the step returns true (success track) without the reload + save; `post_process` re-saves every aggregate and runs even when a fail-fast import stops early |
| `ImportFundFormula#save_row` | internal | **as built:** `max_sequence(fund)` reads `FundFormula.unscoped.where(fund_id:)` — the same rows acts_as_list's shift touches (its `acts_as_list_list` drops every where but the fund's, so soft-deleted formulas count); reset to nil after any normal-path insert or update-only row; originally planned as `@max_seq ||= fund.fund_formulas.maximum(:sequence).to_i`; shortcut iff `k.to_i >= 1 && k > @max_seq`; then `@max_seq = [@max_seq + 1, k].max` on either path |

**Reviewer checks**
- [ ] `lookup[:kpis]` keyed by report id is unique per (report, name, entity, portco) — guaranteed by `kpi.rb:37` approved uniqueness
- [ ] Blank `tag_list` bypasses `lookup[:reports]`
- [ ] `@max_seq` updated after **every** row, shortcut or not

## Controllers, Params and Responses

N/A — no controller change.

## Queries and Indexes

| Query | Shape | Index used |
|---|---|---|
| period reports | `KpiReport.where(entity_id:, portfolio_company_id:, tag_list:, period: %w[Quarter YTD Year])` | existing portco/entity indexes |
| approved KPIs | `Kpi.approved.where(kpi_report_id: ids, entity_id:, name:, portfolio_company_id:)` | `kpi_report_id` |
| grouped attributions | `PortfolioAttribution.where(bought_pi_id: ids).group(:bought_pi_id).sum(:quantity)` | `bought_pi_id` |
| grouped conversions | `StockConversion.where(from_portfolio_investment_id: ids).group(...).sum(:from_quantity)` | FK index |
| grouped as-of sales (phase 8) | `PortfolioAttribution.joins(:sold_pi).merge(PortfolioInvestment.include_proforma.before(date)).where(bought_pi_id: ids).group(:bought_pi_id).sum(:quantity)` | `bought_pi_id` |
| remittance form type (phase 8) | `entity.form_types.where(name: "CapitalRemittance").last` once per call | `entity_id` |
| max sequence | `fund.fund_formulas.maximum(:sequence)` | `fund_id` |

**Reviewer checks**
- [ ] Each query run on dev MySQL (33066) with `EXPLAIN`; no filesort on large tables
- [ ] No `DISTINCT` added; grouped sums carry no `ORDER BY`

## Transactions, Locking and Concurrency

No new transactions. `acts_as_list_no_update` is thread-local (acts_as_list 1.2.6 `no_update.rb:73`) and
scoped to one `create!`. Concurrent writer to the same fund's formulas during an import: `@max_seq` may be
stale → shortcut skipped wrongly only if another process appended in between; mitigated because the
shortcut only applies when the shift UPDATE would match 0 rows **as of the last read** — reviewer to
confirm acceptable (imports are user-initiated, one per fund).

**Reviewer checks**
- [ ] `acts_as_list_no_update` block wraps only the single `create!`

## Background Jobs

| Job | Queue | Retry | Idempotent? |
|---|---|---|---|
| `CapitalCallJob` | serial (unchanged) | unchanged | yes — re-save loop rebuilds batches |
| `KpiCumulateJob` | unchanged | unchanged | yes — `seen` Set is per perform |

**Reviewer checks**
- [ ] No job's arguments change

## External Integrations

N/A — none touched.

## Error Mapping and Logging

Unchanged. D3: `autofill_errors` for a repeated key appear once.

**Reviewer checks**
- [ ] No rescue added around per-record saves

## Project rules checklist

| Rule (CLAUDE.md) | Applies | How |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | use `any?`/`exists?` on new relations |
| Dedup in SQL | Applies | no `.uniq` after pluck |
| Batch bulk ops | Applies | `find_each` everywhere |
| Select only needed columns on `account_entries` | Applies | `setup_call_fees` → `pluck` |
| No speculative eager loads of big associations | Applies | documents preloaded only where `validates_associated` already loads them |
| Doc-gen contexts stay relations | N/A | not touched |
| Date formatting | N/A | no dates rendered |
| MCP ontology | N/A | no ransack/MCP change |
| `IRM/RelationBlankPresent` cop | Applies | rubocop clean on changed files |

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
