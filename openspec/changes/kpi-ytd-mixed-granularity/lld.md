# KPI YTD, Quarter and Year from Mixed Monthly and Quarterly Data — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec: cumulation](specs/startups/kpi-cumulation/spec.md) · [Spec: report comparison](specs/funds/portfolio-report-kpi-comparison/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md).

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

- Calculated rows are identified by `kpis.source = "auto_cumulation"`, with the note prefix "Auto-generated" accepted for
  legacy rows — see [Method Contracts](#method-contracts).
- The planner is pure (no ActiveRecord); only the reconciler writes — see [File Map](#file-map).
- A person's write replaces the marker: an import stamps `source = "upload"`, `KpiApprover` copies `source` when it
  overwrites a calculated row, the Kpi form stamps `manual` — see [Method Contracts](#method-contracts).
- Deletes use the existing hard delete (`Kpi` has no audit trail per `kpi-hard-delete-no-audit`) — see
  [Transactions](#transactions-locking-and-concurrency).
- The fiscal year comes only from the portfolio company or the entity setting, never a Kpi. The old code never read
  either, so companies with a non-default offset see their fiscal years shift — see
  [Configuration and Rollout](#configuration-and-rollout).
- `Kpi.recompute_percentage_change` compares `YTD` groups with the row one year earlier and stores nil when it is
  missing, zero or too large to store; it now groups by owner; other periods are untouched — see
  [Method Contracts](#method-contracts).
- `KpisHelper#kpi_percentage_class` skips the colour and shows "-" for an empty change; Recompute Auto-Fill now runs
  the percentage recompute — see [Method Contracts](#method-contracts) and [Background Jobs](#background-jobs).
- `KpiCumulateJob` takes one lock per company — see [Transactions](#transactions-locking-and-concurrency).
- `grid_view_array` adds `<label>_vs_<tag>_percent` from one in-memory index and no new query — see
  [Queries and Indexes](#queries-and-indexes).
- Existing stored YTD changes change meaning and are corrected by the existing recompute job — see
  [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ② | `app/packs/startups/kpis/services/kpi_date_utils.rb` | Modified | `fiscal_year_start(date, start_month)`, `fiscal_quarter(date, start_month)` |
| ③ ④ | `app/packs/startups/kpis/services/kpi_cumulation_planner.rb` | New | Pure `plan`, `settle_quarters`, `walk` |
| ① ⑤ | `app/packs/startups/kpis/models/concerns/kpi_cumulative.rb` | Modified | `perform_cumulation` and `perform_forward_fill` call planner and reconciler; `fiscal_year_key` uses `KpiDateUtils`; old `process_*` methods removed; the reconciler skips an expected row that exists and is not calculated, before it calls `process_cumulative_kpi` (which the compute path also uses) |
| ⑤ | `app/packs/startups/kpis/models/kpi.rb` | Modified | `calculated_cumulative` scope / predicate |
| ⑦ | `app/packs/startups/kpis/models/kpi.rb` | Modified | `recompute_percentage_change`: groups by owner too; year-earlier comparator for `YTD` groups; nil when missing, zero or too large to store (checked after rounding); other periods unchanged |
| ⑥ | `app/packs/startups/kpis/helpers/kpis_helper.rb` | Modified | `kpi_percentage_class`: no threshold comparison and no colour when `percentage_change` is nil; shows "-" |
| ⑥ | `app/packs/startups/kpis/views/kpis/show.html.erb`, `kpis/_kpi.html.erb` | Modified | Print "-" instead of " %" for an empty change |
| ⑦ | `app/packs/startups/kpis/controllers/kpi_reports_controller.rb` | Modified | `recompute_cumulative` passes `compute_percentage_change: true` |
| ⑤ | `app/packs/startups/kpis/jobs/kpi_cumulate_job.rb` | Modified | One lock per company around the run and the inline percentage recompute; re-queue when busy |
| ⑧ | `app/packs/startups/kpis/models/kpi_report.rb` | Modified | `report_kpis_by_name`: the approved, shown-in-report KPIs of a loaded report, keyed by lower-cased name (shared by both report builders) |
| ⑧ | `app/packs/funds/portfolios/services/portfolio_report_sablon_word_service.rb` | Modified | `grid_view_array` (mirror used for the AI-drafted report export): approved KPIs only, same index |
| ⑧ | `app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb` | Modified | `grid_view_array`: per-report KPI index; comparator tag constant; `<label>_vs_<tag>_percent` for Actual columns |
| ⑨ | `app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb` | Modified | `add_fund_level_data`: `irr` and `moic` on each `<fund>_data`; `fund_ratio_values` (one query of stored Default-scenario ratios); `add_investment_milestones` (`latest_pi`, `earliest_pi`) |
| ⑤ | `app/packs/startups/kpis/services/kpi_workbook_reader.rb` (`save_kpi_entry`) | Modified | Stamp `source = "upload"` on the rows an import writes |
| ⑤ | `app/packs/startups/kpis/services/kpi_approver.rb` | Modified | When it overwrites an approved row, copy `source` from the uploaded row, blank included |
| ⑤ | `app/packs/startups/kpis/controllers/kpis_controller.rb` (`create`, `update`) | Modified | Stamp `source = "manual"` when a person saves a value |
| Tests | `features/startup/kpi_cumulate_mixed_granularity.feature`, `kpi_forward_fill_mixed_granularity.feature`, `kpi_cumulate_cleanup.feature` | New | Worked examples |
| Tests | `features/startup/kpi_cumulate.feature`, `features/startup/kpi_extended_aggregation.feature` | Modified | Scenarios that encode the old Quarter and forward-fill rules (listed in tasks.md 2.3 and 4.1); `kpi_cumulate_multi_year.feature` and `kpi_autofill_on_approval.feature` are run, not edited |
| Tests | `features/step_definitions/kpi.rb`, `kpi_autofill_on_approval_steps.rb` (and one new steps file only if needed) | Modified | Optional `notes` and `source` columns on the shared KPI step; uploaded Quarter and "no KPI" steps; the nil-mapping row is seeded as a calculated row |
| Tests | `features/startup/kpi_ytd_yoy_percentage_change.feature`, `features/step_definitions/kpi_percentage_change_steps.rb` | New | ⑦ worked examples and their steps |
| Tests | `features/fund/portfolio_report_kpi_vs_budget.feature`, `features/step_definitions/portfolio_report_kpi_steps.rb` | New | ⑧ worked examples and their steps (rows are built through the generator and the Sablon service without rendering a document) |
| Tests | `features/fund/portfolio_report_fund_metrics.feature`, `features/step_definitions/portfolio_report_fund_metrics_steps.rb` | New | ⑨ worked examples and their steps (fund-level context built through the generator without rendering a document) |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here
- [ ] The planner file has no ActiveRecord or Rails reference
- [ ] Files follow the pack layout

---

## Schema Detail

N/A — no table or column changes. `kpis.source` (string, limit 100, null allowed, existing) gains the values
`auto_cumulation` (calculated), `upload` (import) and `manual` (Kpi form). Blank, `upload` and `manual` all mean a
person wrote the row.

**Reviewer checks**
- [ ] Only the reconciler, the import, the approver and the Kpi form write `kpis.source` (the Kpi show page only displays it)

---

## Method Contracts

| Method | Signature | Contract |
|---|---|---|
| `KpiCumulationPlanner.plan` | `(months:, quarters:, fy_start_month:, mode:, today:, tag:) -> Array<Hash>` | Months are `[{as_of:, value:}]`; quarters are `[{as_of:, value:, calculated:}]`; mode is `:sum` or `:last`; returns `[{period:, as_of:, value:}]` for Quarter, YTD, Year. Pure. Missing data is never zero |
| `#settle_quarters` | per fiscal year | Uploaded quarter kept; 3 months present gives a calculated quarter; else none |
| `#walk` | per fiscal year | `:sum`: base per quarter; month YTDs while contiguous; quarter total from 3 months, else the quarter row, else stop; Year after Q4. `:last` (forward fill) never stops at a gap: YTD at each month with a value (a month wins over a Quarter figure on the same date), YTD at a quarter end only a Quarter figure covers; Quarter only from 3 months; Year = Q4 value only when all 4 quarters are covered |
| `KpiCumulative#reconcile_cumulative_kpis` | `(expected, existing)` | Upsert by (period, as_of, tag) via `process_cumulative_kpi`; an expected row that already exists and is not calculated (uploaded or manual) is skipped, not overwritten; destroy existing calculated rows not expected; never touch rows that are neither expected nor calculated. After the transaction commits, when the KPI's mapping has RAG rules, call `cascade_dependent_rag_recompute!` for each deleted row (a delete does not trigger it today) |
| `Kpi.calculated_cumulative` | scope | `source = 'auto_cumulation'`, or `source` blank and `notes LIKE 'Auto-generated%'` (legacy), on Quarter/YTD/Year reports |
| `process_cumulative_kpi` | existing | Sets `source = 'auto_cumulation'` when it writes. Stays a plain writer: the compute path calls it for every period, including Month, and keeps updating its own rows |
| `KpiApprover.call` | `(kpi_id, user_id)` | When it overwrites an approved row it also copies `source` from the uploaded row, blank included, so an upload over a calculated row ends as `upload` |
| `KpiCumulateJob#perform` | existing | Takes one lock per company id (ids in sorted order) before it reads anything and releases it after the inline percentage recompute; see Transactions |
| `Kpi.recompute_percentage_change` | `(kpis)` | Groups by period, name, tag and `owner_id` (the job already groups this way). For `YTD` groups index rows by `as_of`; comparator = row at `as_of.prev_year`, month-end matched (`as_of.end_of_month == as_of` then `as_of.prev_year.end_of_month`). Comparator nil or value zero gives nil. Other periods keep `each_cons(2)` previous row. Zero divisor gives nil as today. The change is rounded to 2 decimals; an absolute value above 9,999.99 gives nil. Every row in the list is recomputed; the old `force:` option had no caller that passed false and is removed |
| `KpisHelper#kpi_percentage_class` | `(kpi, investor_kpi_mapping)` | When `percentage_change` is nil: no threshold comparison, no colour class, display "-". Otherwise as today |
| `KpisHelper#kpi_percentage_display` | `(kpi) -> String` | "-" when `percentage_change` is nil, else "<value> %"; used by `kpi_percentage_class` and the KPI show and list views |
| `KpiReport#report_kpis_by_name` | `() -> Hash` | `{ name.downcase => kpi }` of the loaded `kpis` that are approved and whose mapping has `show_in_report`, first one wins; no query when `kpis` and their mappings are preloaded |
| `PortfolioReportDocGenerator#grid_view_array` | `(portfolio_company, end_date, category: nil) -> Array<OpenStruct>` | Builds `index[report.id][name.downcase]` once from the `approved` `kr.kpis` whose mapping has `show_in_report` (first match wins); the existing `<label>` and `<label>_percent` keys read from this index, so unapproved figures give "N/A". For each Actual report adds `"#{label}_vs_#{tag}_percent"` for each tag in `COMPARATOR_TAGS` (`["Budget"]`): comparator report = same period, same `as_of`, that tag; value = `actual / comparator * 100`, or `"N/A"` when no report, no KPI (an unapproved KPI is not in the index), nil values, or comparator zero |

- Aggregate: `:sum` adds; `:last` takes the latest value. Both use `BigDecimal` from `kpis.value` (decimal 20,6), never Float,
  to keep the sums exact. The old code used `to_f`.
- Future guard: Actual rows with `as_of > Date.current` are not expected; Budget and IC are exempt.
- Walk is per fiscal year; the loop key is `fiscal_year_start`.
- Percentage and ratio use `BigDecimal` from `kpis.value`; the stored change keeps decimal(6,2). The change is rounded
  to 2 places first; a rounded absolute value above 9,999.99 would overflow the column, so it is stored as nil (clamp to
  nil, task 6.2) and never aborts the group. Rounding first matters: 9,999.995 passes a check on the raw value but
  rounds to 10,000.00.
- Each row has `data_type` = the mapping's `data_type`, lower-cased, set once per row (H15).
- Actual-against-budget values are raw numbers (not rounded or delimited), like the existing row keys.
- ⑨ `latest_pi` / `earliest_pi`: on or before the end date: latest is the last investment, buy or sale
  (`order investment_date desc, id desc`); earliest is the first `buys` row (`order investment_date asc, id asc`); with none, a placeholder (`investment_date` nil, empty
  `custom_fields`) so a template that reads them does not fail. The stake is read by the template from `custom_fields`.
- ⑨ `irr` / `moic`: `FundRatio.default` rows with `owner_type "Investor"`, `owner_id` the company, `fund_id` in the
  company's funds, `name` IRR or MOIC, `computation_context_id` nil, `end_date` up to the report's end date; the
  latest `end_date` (then `id`) per fund and name wins; absent is "N/A". Stored ratios are read, never recomputed.

**Reviewer checks**
- [ ] The planner returns the Jun, Jul, Aug YTD values from H1 exactly (13,271,278.17 and 16,293,230.03)
- [ ] `walk` keeps `base` separate from the within-quarter running total
- [ ] No `to_f` remains in the cumulation path
- [ ] An uploaded figure approved over a calculated row ends with `source = "upload"` and survives the next recompute (E30)
- [ ] An import-then-approve of a figure that was staged before deploy (blank `source`) also replaces the marker
- [ ] The reconciler skips an expected row that exists and is not calculated
- [ ] The compute path still updates its own Month, Quarter, YTD and Year rows
- [ ] A forward-fill gap (July missing) leaves August's YTD in place (E36)
- [ ] With a Quarter figure at a quarter end, a missing middle month and the quarter-end month present, the quarter-end YTD is base plus the Quarter figure and the month is not added on top (E38)
- [ ] A forward-fill Quarter balance at a quarter end with no month gives YTD equal to that balance and is not added to earlier quarters; a cumulate KPI still adds it to the earlier quarters (E39, H3)
- [ ] Deleting a calculated Budget YTD row re-evaluates the Actual YTD row's status, once, after the commit, and not at all when no RAG rules are set (E37)
- [ ] YTD change for Jun-26 is 22.69 when Jun-25 YTD is 7,000,000 and Jun-26 YTD is 8,588,636; Jul-26 with no Jul-25 is nil
- [ ] No fallback path exists when the year-earlier row is missing
- [ ] Month, Quarter and Year groups still use the previous row
- [ ] A YTD change above 9,999.99 in absolute value, or one that rounds to 10,000.00, is stored as nil and the rest of the group is still processed
- [ ] Two owners' YTD rows for the same KPI, tag and dates are each compared with their own owner's year-earlier row (E33)
- [ ] A YTD cell with an empty change and a mapping with thresholds renders "-" with no colour and no error (E31)
- [ ] `_vs_budget_percent` is 92 for Actual 92 and Budget 100, and "N/A" for missing or zero Budget
- [ ] No `_vs_` key is added to Budget, IC or untagged columns
- [ ] Each row has `data_type` ("percentage" for a percentage mapping) (H15)
- [ ] The index holds approved KPIs only; an unapproved Actual or Budget gives "N/A" and an unapproved figure is "N/A" in `<label>` and `<label>_percent` too
- [ ] The KPI screen grid partials and `KpisHelper#grid_view_array` (no caller in the app) are untouched
- [ ] The latest investment can be a sale (its stake is then blank); the earliest is always the first buy across all funds (E44, H13)
- [ ] A buy dated after the end date is not used (E45); with no buy both keys are placeholders and the report still generates (E46)
- [ ] `irr` and `moic` come from the company's own Default-scenario ratio for that fund as of the end date, never the fund's own ratio or a scenario's (E42, E43)

---

## Controllers, Params and Responses

N/A — no new endpoints. `KpisController` approval and "Recompute Auto-Fill" actions are unchanged.

**Reviewer checks**
- [ ] The approval notice text is unchanged

---

## Queries and Indexes

| Read | Shape | Index |
|---|---|---|
| Months | existing `fetch_related_monthly_kpis` | existing composite index on `kpi_reports` |
| Quarters | existing `fetch_related_quarterly_kpis`; calculated rows now included | same |
| Calculated rows | entity, company, name, tag, periods `Quarter`, `YTD`, `Year`, preloaded `kpi_report` | existing |
| Percentage change | existing grouped load in `KpiPercentageChangeJob` (approved, joins and preloads `kpi_report`); year-earlier row picked from the loaded group in memory | existing |
| Report KPI rows | existing `portfolio_kpi_reports.includes(kpis: :investor_kpi_mapping)`; one in-memory index per report replaces `kr.kpis.show_in_report` (a SQL scope run per mapping per report) | existing |
| Report fund ratios | one `fund_ratios` query for all the company's funds (`pluck` of fund, name, value), latest per fund and name picked in memory | existing `fund_id` and `owner` indexes |

**Reviewer checks**
- [ ] `preload`, not `includes`, with `joins(:kpi_report)`, as the existing comments require
- [ ] No query per row inside the walk
- [ ] `grid_view_array` issues no query per mapping or per report (assert the query count does not grow with the number of mappings)
- [ ] Percentage change picks the year-earlier row from the loaded group, not by a query per KPI
- [ ] `add_fund_level_data` issues one `fund_ratios` query however many funds the company has

---

## Transactions, Locking and Concurrency

- One transaction per KPI reconcile (upserts plus deletes) so a failure does not leave half a walk. Failures inside are
  collected into `@autofill_errors` and the transaction is rolled back for that KPI only.
- One lock per company. `KpiCumulateJob#perform` takes a MySQL `GET_LOCK` named `kpi_cumulate:<company id>` before it
  reads anything and releases it (`ensure`) after the inline percentage recompute. It follows the pattern
  `UpdateInvestor#with_entity_email_lock` already uses (no lock on SQLite, which the test database cannot contend), and
  takes and releases the lock on one connection (`ActiveRecord::Base.with_connection`), because `GET_LOCK` belongs to a
  connection. Several company ids are locked in id order.
- The lock waits (up to 60 seconds). If it is still busy the job re-queues itself 1 minute later, at most 10 times,
  then reports through the existing error notification. Waiting rather than skipping means a later approval is never
  dropped, and the run that goes last always reads the final data. The lock is one small method that returns false when
  busy, so a scenario can make it busy (E34).
- A lock per period would not help: every run plans the whole series and the reconciler can delete across fiscal
  years, so runs for different periods still overlap.
- The standalone "Recompute Percentages" job is not locked. It writes only `percentage_change`; a run that overlaps a
  cumulation is corrected by the next recompute.
- Lock statements bypass the query cache (`connection.uncached`). A job runs inside the Rails executor, which turns the query
  cache on; a `SELECT GET_LOCK` or `RELEASE_LOCK` served from the cache never reaches MySQL, so the lock would be neither
  taken nor released. `UpdateInvestor#with_entity_email_lock` has the same exposure and was left as it is.
- Deletes are hard deletes (no audit, per the `kpi-hard-delete-no-audit` change).

**Reviewer checks**
- [ ] A rollback for one KPI does not abort the other KPIs in the job
- [x] `kpis` has no `deleted_at` column, so deletes are hard (checked in `db/schema.rb`)
- [ ] The lock is released when the run raises
- [ ] A busy lock re-queues the job and changes no figure (E34)

---

## Background Jobs

`KpiCumulateJob` keeps its `report_ids` scoping, which still selects which KPIs are processed, and gains the company
lock (above). `KpiPercentageChangeJob` still runs inline afterwards when `compute_percentage_change` is true and now
also fixes YTD changes. It recomputes the whole company with `force: true`, so a removed or newly written YTD row is
reflected in the next year's change at once.

Who passes the flag: `KpiApproveService` and `InvestorKpiMappingDelete` already do. `KpiReportsController#recompute_cumulative`
did not, so a Recompute Auto-Fill left new YTD rows on the column default and a removed row's dependants stale. It now
passes `compute_percentage_change: true` (E32). The import's own `KpiCumulateJob` call (`KpiWorkbookReader#extract_kpis`)
does not pass it and stays that way: an import writes unapproved rows only, so the approved figures, and their
changes, move at approval. Cleanup of legacy rows done by an import-started run is followed by the rollout recompute.

**Reviewer checks**
- [ ] Cleanup of stale rows also runs on `force: true` recompute
- [ ] After the reconciler removes a YTD row, the inline percentage job leaves the next year's YTD change nil (E16)
- [ ] The Recompute Auto-Fill action enqueues the job with `compute_percentage_change: true` (E32)

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Failure | Mapping |
|---|---|
| Save fails | `record_autofill_save_error` (existing) |
| Destroy fails | Same, with period and as_of |

Logging: one info line per KPI with counts (expected, upserted, removed) at the existing `Rails.logger.info` points.

**Reviewer checks**
- [ ] Removed rows are logged with period and as_of

---

## Security Review

All queries keep `entity_id` scoping. No new params. No user input reaches the planner.

**Reviewer checks**
- [ ] The calculated-row scope is always combined with `entity_id` and `portfolio_company_id`

---

## Configuration and Rollout

- Two PRs (see tasks.md, Delivery): PR 1 is the cumulation (phases 1 to 5, including the fiscal-year shift and the
  cleanup); PR 2 is the YTD year-over-year change and Actual against Budget (phases 6 and 7). Until PR 2 is deployed,
  YTD changes keep the old previous-month value.
- Fiscal start: `KpiDateUtils.resolve_fiscal_year_start_month` only (portfolio company, then entity setting, then the
  regional default). The offset is never on a Kpi. The old `fiscal_year_key` asked the Kpi first, which always returned
  a date, so company and entity offsets were never read. Task 1.1 lists the companies and entities whose offset differs
  from the regional default; their fiscal years shift on the next recompute, their calculated YTD and Year rows are
  recalculated, and the old ones are removed by the cleanup.
- No feature flag. Existing wrongly calculated rows are removed on the next approval or recompute per company; the agreed
  first run is the test investor, then a manual "Recompute Auto-Fill" for others.
- YTD percentage change backfill: after the PR 2 deploy, run `KpiPercentageChangeJob` (force) per company, starting with the test
  investor; the existing "Recompute Percentage Change" action does the same per report. Until it runs, YTD cells keep the
  old previous-month value.
- Actual against Budget has no rollout: it exists only while a report is generated.

**Reviewer checks**
- [ ] The list of companies and entities with a non-default offset is reviewed before the first recompute
- [ ] Rollout order: deploy, recompute the test investor, inspect, then others
- [ ] YTD percentage change backfill run for the test investor before the others

---

## Test Plumbing

Cucumber only. Reuse the Monthly KPI Reports steps from `kpi_cumulate.feature`. New steps: create an uploaded Quarter KPI
(`source` blank or `upload`), approve an uploaded figure over a calculated row, and assert absence of a KPI for a
period. Freeze "today" for the future-date guard using the existing time-travel step. For E34, make the company lock
busy and assert the job is queued again with no figure changed.

New steps for ⑦: set a Kpi's `percentage_change`, run the percentage-change recompute, assert a YTD change equals a value
or is empty; show the KPI grid for a YTD KPI with an empty change and a mapping with a threshold (E31); assert the
Recompute Auto-Fill action enqueues `KpiCumulateJob` with `compute_percentage_change: true` (E32). New steps for ⑧: build the report's KPI rows through the generator with Actual and Budget Kpi reports,
assert a row key equals a value or "N/A", and count queries around the call. New steps for ⑨: create buys in named funds (optionally with a stake) and sales, store fund ratios owned by the company, build the generator's fund-level context, and assert the latest and earliest investment and each fund's `irr` and `moic`.

**Reviewer checks**
- [ ] Every H/E/X in design.md has one scenario with an ID comment above it

---

## Project Rules Checklist

| Rule | Applies / N/A | Note |
|---|---|---|
| Large-table hygiene (preload, index, no N+1) | Applies | Reuse existing fetches |
| Date formatting | N/A | No new display |
| Tenant scoping (`entity_id`) | Applies | All queries |
| MCP ontology | N/A | No model or field exposed |
| IRM cops (RuboCop, Brakeman) | Applies | Run on modified files |
| No comments in specs | Applies | Code comments carry H/E/X IDs; none in `.feature` beyond the required ID line |

**Reviewer checks**
- [ ] RuboCop is clean on the modified files
- [ ] Brakeman has no new findings

---

## Sign-off

| Reviewer | Date | Decision (approved / changes requested) |
|---|---|---|
| | | |
