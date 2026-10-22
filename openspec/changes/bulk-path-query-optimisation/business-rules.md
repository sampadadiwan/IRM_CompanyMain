# Faster bulk jobs — Business rules and worked examples

> Linked from [design.md](design.md#worked-examples). Every row is exactly one Cucumber scenario in
> the feature named in its row (one feature per phase, see tasks.md), with an `# ID — …` comment.
> "Queries" = SQL statements counted from the named call sites with `sql.active_record`.

## Shared setup

| Name | Data |
|---|---|
| Fund Alpha | 3 commitments (Acme LP ₹10 cr, Beta Trust ₹5 cr, Gamma HUF ₹2 cr), call "Q3" 10% |
| Company Acme | KPI mapping Revenue (cumulate); Monthly Revenue Apr–Sep 2026 = 10,12,11,13,14,15 (fiscal year from April) |
| Fund Beta | Formulas sequences 1,2,3 (existing) |
| Fund Gamma | 2 portfolio investments in one aggregate; 1 attribution of 100 units, 1 conversion of 20 units |

## Happy Path

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| H1 | Remittance re-save loads related rows per batch | Fund Alpha, call Q3 | remittances are generated | 3 remittances with the same amounts as today; commitment/investor/fund lookups from the re-save loop ≤ 1 each per batch | Capital call generation produces the same remittances; Remittance follow-up saves load related records per batch | features/fund/bulk_query_remittances.feature |
| H2 | Un-verify of a remittance with documents loads them in one pass | H1 done; the first remittance has 3 documents | a payment is recorded for it | its payment date moves to the payment's; document folder lookups from Document#setup_folder = 0 (3 without the preload; 47 → 35 queries in total) | Remittance follow-up saves load related records per batch | features/fund/bulk_query_remittances.feature |
| H3 | KPI cumulation reads periods once per name | Company Acme, Revenue Apr–Sep 2026 = 10,12,11,13,14,15 (FY from April) | the cumulation job runs | Q1=33, Q2=42, YTD-Sep=75; queries from process_cumulative_kpi ≤ 72 (200 without the lookup) | Identical results from bulk jobs | features/startup/bulk_query_kpi_cumulation.feature |
| H4 | Workbook import reads each report's KPIs once | Company MyFavStartup, MIS sample.xlsx with 5 mapped KPIs | the workbook is imported | 17 reports extracted, all KPIs staged unapproved; queries from save_kpi_entry ≤ 85 for 85 cells (340 without the per-report maps) | Shared data read once per batch | features/startup/bulk_query_kpi_import.feature |
| H5 | Formula import appends without shifting | Fund Beta with formulas at 1, 2, 3 | a sheet with sequences 4, 5, 6 is imported | order Existing 1–3 @1–3, New 1–3 @4–6; sequence-shift statements from save_row = 0 (3 without the fix) | Identical results from bulk jobs | features/fund/bulk_query_formula_import.feature |
| H6 | Portfolio re-value reads quantities per batch | Fund Gamma: 3 buys of 200, 2 sells of 100 attributed to them | the fair value recompute job runs | every investment's sold / transferred / net quantities unchanged; queries from set_buy_quantities = 0 (6 without the preload) | Portfolio re-valuation totals per batch | features/fund/bulk_query_portfolio.feature |
| H7 | Verified generation with payments skips per-remittance lookups | Fund Alpha, call Q3 generated already verified | remittances and their payments are generated | one payment per remittance of its call amount; commitment lookups from set_call_amount = 0 (6 without the batch preload) | Remittance follow-up saves load related records per batch | features/fund/bulk_query_remittances.feature |
| H9 | Call generation reads the remittance form type once (phase 8) | Fund Alpha's entity has a "CapitalRemittance" form type; call Q3 | remittances are generated | every remittance carries that form type; form-type lookups from setup_form_type = 0 (3 without the fix) | Shared data read once per batch | features/fund/bulk_query_remittances.feature |
| H10 | A past-date portfolio view reads every holding's quantities in grouped queries (phase 8) | Fund Gamma: 3 buys of 200, 2 sells of 100 attributed to them, 1 conversion of 20 | the aggregate is valued as of a past date | each investment's net quantity, FMV and the aggregate's totals equal the live per-investment calculation; SUMs from set_buy_quantities and net_quantity_on = 0 (4 per buy without the fix) | Portfolio re-valuation totals per batch | features/fund/bulk_query_portfolio.feature |
| H8 | Re-generating an unchanged call does not touch the fund (found in review) | Fund Alpha, call Q3 already generated | the call is generated again | the fund's updated_at is unchanged (a control scenario: a first generation does touch it); fails on the earlier code, which touched it on every run | Identical results from bulk jobs | features/fund/bulk_query_remittances.feature |

## Edge Cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| E1 | Cumulative report created mid-job is reused | Company Acme, no Quarter report for Q2 | cumulation runs | exactly one Q2 Quarter report; YTD uses it | A cumulative report created for one period is reused | features/startup/bulk_query_kpi_cumulation.feature |
| E2 | Re-importing the same workbook updates its KPIs | the workbook imported once | it is imported again | the staged KPIs are the same rows; no report has two staged KPIs for one name and mapping | A repeated workbook cell updates the KPI it created | features/startup/bulk_query_kpi_import.feature |
| E3 | D3: a KPI name held by several reports is cumulated once | the six monthly reports all hold Revenue | the cumulation job runs | YTD-Sep = 75; one cumulation lookup (16 without the repeat skip) | Identical results from bulk jobs | features/startup/bulk_query_kpi_cumulation.feature |
| E4 | Blank tag keeps live lookup | Acme KPI report with blank tag | cumulation runs | target report found as today (tag-less) | Blank KPI tag keeps the live lookup | features/startup/bulk_query_kpi_cumulation.feature |
| E5 | Formula inserted before existing shifts them | Fund Beta | sheet row sequence 2 | new formula at 2; old 2,3 → 3,4 | Formula placed before existing formulas still shifts them | features/fund/bulk_query_formula_import.feature |
| E6 | Duplicate sequences in one sheet | Fund Beta | rows 4, 4, 4 imported | New 3 @4, New 2 @5, New 1 @6 — as today (the first row takes the shortcut, the next two shift) | Formula placed before existing formulas still shifts them | features/fund/bulk_query_formula_import.feature |
| E7 | Formula with blank or 0 sequence | Fund Beta | sheet row with blank sequence | appended at 4, as today | Formula placed before existing formulas still shifts them | features/fund/bulk_query_formula_import.feature |
| E9 | Investments with no sales or conversions | Fund Gamma: 2 buys of 200, nothing else | the recompute job runs | sold and transferred quantity 0 on each buy, as an empty SUM gives | Portfolio re-valuation totals per batch | features/fund/bulk_query_portfolio.feature |
| E10 | D4: an investment import's aggregate totals | 3 buys (100, 150, 250 units) imported into one aggregate | the import completes | 3 processed, 0 failed; aggregate quantity / bought / sold / average cost match its investments; queries from compute_avg_cost ≤ 18 (36 without D4 — the 18 left come from each new valuation re-valuing the investments) | Identical results from bulk jobs | features/fund/bulk_query_portfolio.feature |
| E12 | Entity with no CapitalRemittance form type (phase 8) | Fund Alpha's entity has none | remittances are generated | the remittances have no form type, as today; generation succeeds | Identical results from bulk jobs | features/fund/bulk_query_remittances.feature |
| E13 | Proforma sale and a sale after the as-of date (phase 8) | 1 buy of 200 (2025-01-01); sales of 50 on 2025-03-01 (then made proforma) and 2025-09-01 | the aggregate is valued as of 2025-06-30 | the buy's net_quantity_on is 200 live and preloaded: both sales left out — the later by date, the proforma one because the sold_pi join's ON clause keeps the default `proforma = FALSE` (existing behaviour, kept; `set_buy_quantities`, which doesn't join, does count it) | Identical results from bulk jobs | features/fund/bulk_query_portfolio.feature |
| E11 | A source KPI edited between two runs is seen by the second | H3 run done | April Revenue changed 10 → 20, job re-run | Q1 = 43, YTD-Sep = 85 | A rule changed between two jobs is seen by the second | features/startup/bulk_query_kpi_cumulation.feature |

## Error Cases

| # | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|
| X1 | Invalid document still blocks the save | remittance with an invalid attached document | unverify after payment | save fails with the same error; earlier remittances stay saved | Documents are still validated on save; A failing record fails the same way | features/fund/bulk_query_remittances.feature |
| X2 | A failed cumulative save is reported once | every cumulative save fails | the cumulation job runs | error email sent; "Could not save Quarter cumulative for 'Revenue' as of 2026-06-30" appears once (6 times without the repeat skip) | A failing record fails the same way | features/startup/bulk_query_kpi_cumulation.feature |
| X3 | Control for X1: a valid remittance takes the new payment's date | H1 done, no invalid document | a payment dated 2099-01-01 is recorded | the remittance's payment date becomes 2099-01-01 | A failing record fails the same way | features/fund/bulk_query_remittances.feature |
| X4 | A RAG status re-judged mid-run by the cascade ends up right (found in review) | Acme with a PriorPeriod RAG rule; first run leaves Q2 green | April 10 → 40 and July 13 → 50, job re-run | Q2 = 79 and its RAG is green (the cascade marked the stored Q2 red when Q1 became 63; Q2's own save must re-judge it). Passes on the earlier code too: the YTD-Sep save, same date as Q2, cascades and heals it — an outcome guard, not a reproduction | A failing record fails the same way | features/startup/bulk_query_kpi_cumulation.feature |

## Dropped

- **E8 (call with more than 1,000 remittances, two batches)** — dropped 2026-10-22 with the user's agreement. It needs 1,001 commitments built through the full factory/callback chain (many minutes per run) and would only prove that `find_each` splits at 1,000, which is Rails' own behaviour; H1 and H7 already prove every remittance is re-saved with its related records from the batch.
