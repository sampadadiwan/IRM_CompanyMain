# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Standing rules:** no change to existing `.feature` / step-definition files; code comments name the
> H/E/X IDs they implement; every new query run on dev MySQL (33066) with `EXPLAIN`; rubocop clean.

## 1. Query-count test support

- [x] 1.1 Add `features/step_definitions/query_budget_steps.rb`: steps that count `sql.active_record` events per call-site file:line during a step (`I count queries from {string}` / `at most {int} queries came from {string}`). Verify: a throwaway scenario counting a known query passes, then delete it.

## 2. Capital remittance chain and document checks (H1, H2, H7, X1, X3)

- [x] 2.1 `CapitalCallJob` re-save loop → `capital_remittances.includes(:capital_commitment, :fund, :entity, investor: :investor_entity, documents: [:folder, :form_type, :e_signatures, :stamp_papers, :user, :entity]).find_each`; comment `# H1`. Verify: `features/fund/capital_calls.feature` green.
- [x] 2.2 Wrap `generate_remittance_payments` in `Fund.no_touching`; single `@capital_call.fund.touch` after it (in `ensure`). Verify: `capital_call_live_remittances.feature` green.
- [x] 2.3 `CapitalRemittancePayment#unverify_remittance`: `ActiveRecord::Associations::Preloader` after `reload` with the same association list; comment `# H2 / X1`. Verify: `capital_remittance_verify.feature` green.
- [x] 2.4 `setup_call_fees` → `pluck(:name, :reporting_date, :amount_cents)`; `ImportCapitalRemittance` passes `entity:`. Verify: `fund_import.feature` green.
- [x] 2.5 Write `features/fund/bulk_query_remittances.feature` (H1, H2, H7, X1, X3, each with `# ID — …` comment). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/bulk_query_remittances.feature` and confirm green before phase 3.

## 3. KPI cumulation (H3, E1, E3, E4, E11, X2)

- [x] 3.1 `KpiCumulateJob#run_cumulation`: `preload(:investor_kpi_mapping)` on the KPI `find_each`; D3 `seen` Set of `[name, kpi_report.tag_list, investor_kpi_mapping_id]` skipping repeats; comment `# E3`. Verify: `kpi_cumulate.feature` green.
- [x] 3.2 `KpiCumulative`: build per-autofill `lookup` (reports by `[period, as_of]`, approved KPIs by `kpi_report_id`); `process_cumulative_kpi(..., lookup:)` consults it, writes created reports/KPIs back (`# E1`); blank `tag_list` bypasses it (`# E4`); `find_or_initialize_by` after a miss → `new`. Verify: `kpi_cumulate_multi_year.feature`, `kpi_extended_aggregation.feature` green.
- [x] 3.3 `Kpi` cascade sibling query `preload(:investor_kpi_mapping)`. Verify: `kpi_rag_status_examples.feature` green.
- [x] 3.4 Write `features/startup/bulk_query_kpi_cumulation.feature` (H3, E1, E3, E4, E11, X2). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/bulk_query_kpi_cumulation.feature` and confirm green before phase 4.

## 4. KPI workbook import (H4, E2)

- [x] 4.1 `KpiWorkbookReader`: per report (beside `@results`) preload unapproved (order by id, first per `[name, mapping_id]`) and approved (keyed `[name, mapping_id]`, no entity filter) KPIs; consult in `save_kpi_entry`; write the saved KPI back (`# E2`); assign `kpi.entity` once. Verify: `kpi_workbook_reading.feature`, `kpi_upload_validation.feature` green.
- [x] 4.2 Write `features/startup/bulk_query_kpi_import.feature` (H4, E2). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/bulk_query_kpi_import.feature` and confirm green before phase 5.

## 5. Fund formula import (H5, E5, E6, E7)

- [x] 5.1 `ImportFundFormula`: `@max_seq` read once; `FundFormula.acts_as_list_no_update { create! }` only when `k >= 1 && k > @max_seq`; update `@max_seq` after every row. Verify: `fund_import.feature`, `account_entries.feature` green.
- [x] 5.2 Write `features/fund/bulk_query_formula_import.feature` (H5, E5, E6, E7). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/bulk_query_formula_import.feature` and confirm green before phase 6.

## 6. Portfolio computations (H6, E9, E10)

- [x] 6.1 `PortfolioComputations#set_buy_quantities(quantities: nil)`; re-value jobs build grouped sums per batch and pass them. Verify: `portfolio.feature`, `aggregate_portfolio_investments.feature` green.
- [x] 6.2 `AggregatePortfolioInvestment#as_of`: compute `net_quantity_on` parts once (sells stay SQL). Verify: `fund_ratio*.feature` green.
- [x] 6.3 D4: skip per-PI aggregate reload+save in `compute_avg_cost` when PortfolioInvestment counter updates are skipped (import). Verify: `investment_import.feature` green.
- [x] 6.4 Write `features/fund/bulk_query_portfolio.feature` (H6, E9, E10). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/bulk_query_portfolio.feature` and confirm green before phase 7.

## 7. Regression and measurement

- [x] 7.1 Run `pcuc -n 4 features/fund features/funds features/core features/startup` (background) and confirm the only failures are the known flaky set (allocation `No unique index`, kpi timeouts, distributions:272).
- [x] 7.2 Re-run with `LOGS=debug BULLET=1` and the analyser from `tmp/query_fixes_core.md`; record before/after per-site counts in `tmp/query_fixes_core.md`. Verify: each chain's site counts drop as stated in design.md Performance.

## 8. Found in the final debug run (H9, H10, E12, E13) — approved 2026-10-22

- [x] 8.1 `CapitalCallJob#create_remittances`: read the call entity's "CapitalRemittance" form type once before the loop (same query as `setup_form_type`) and pass `form_type:` to each `CapitalRemittance.new`; nil passes nil (E12 — `setup_form_type` then queries per record, as today). Verify: `capital_calls.feature` green.
- [x] 8.2 `PortfolioInvestment.with_net_quantities_on(records, date)`: one grouped SUM of sold quantities by `bought_pi_id`, joining `sold_pi` with `include_proforma.before(date)` (the rows `net_quantity_on` sums — proforma sales stay out, E13), and one grouped SUM of conversions keyed by `[pi_id, fund_id]` (the live sum is `fund.stock_conversions`). `net_quantity_on(date)` uses the pair when its date matches, else sums live. `AggregatePortfolioInvestment#as_of` loads its investments to an array and calls `with_buy_quantities(pis, date: end_date)` and `with_net_quantities_on(pis, end_date)` before `as_of`. Verify: `portfolio.feature`, `fund_ratio*.feature`, `aggregate_portfolio_investments.feature` green.
- [x] 8.3 Scenarios H9, E12 in `features/fund/bulk_query_remittances.feature` and H10, E13 in `features/fund/bulk_query_portfolio.feature`, each with `# ID — …` comment, each failing without its fix where it counts queries. Run both features and confirm green.
