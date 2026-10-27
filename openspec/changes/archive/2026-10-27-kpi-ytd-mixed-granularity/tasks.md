# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Each scenario carries a comment line above it naming its H/E/X ID. Code branches carry the same IDs.
> Design references: [design.md](design.md#worked-examples), [lld.md](lld.md).

## Delivery: two pull requests

The change ships as two PRs. The file limit counts everything outside `openspec/` (app code, features, step definitions).

| PR | Branch | Phases | Scope | Planned files |
|---|---|---|---|---|
| 1 | `kpi-compute-fixes` | 1 to 5 | Cumulation: fiscal calendar, calculated-row marker, planner, reconciler, forward fill, cleanup, company lock | 15 to 16 (ceiling 16): 8 app files (`kpi_date_utils.rb`, `kpi_cumulation_planner.rb`, `kpi_cumulative.rb`, `kpi.rb`, `kpi_workbook_reader.rb`, `kpi_approver.rb`, `kpis_controller.rb`, `kpi_cumulate_job.rb`), 3 new features, 2 changed features (`kpi_cumulate.feature`, `kpi_extended_aggregation.feature`), 2 to 3 step files (`step_definitions/kpi.rb`, `kpi_autofill_on_approval_steps.rb`, and one new file only if the new steps do not fit in `kpi.rb`) |
| 2 | `kpi-compute-fixes-1` | 6 and 7 | YTD year-over-year change, Actual against Budget, and the stake, first investment date, IRR and MOIC in the report | 14 (ceiling 15): 8 app files (`kpi.rb`, `kpi_report.rb`, `kpis_helper.rb`, `kpis/show.html.erb`, `kpis/_kpi.html.erb`, `kpi_reports_controller.rb`, `portfolio_report_doc_generator.rb`, `portfolio_report_sablon_word_service.rb`), 3 new features, 3 new step files (`kpi_percentage_change_steps.rb`, `portfolio_report_kpi_steps.rb`, `portfolio_report_fund_metrics_steps.rb`) |

Scenario E16 relies on the cleanup from PR 1, so PR 2 builds on it. PR 1 was committed on `kpi-compute-fixes` before it was
merged, so `kpi-compute-fixes-1` was created from that branch; once PR 1 merges, rebase `kpi-compute-fixes-1` onto main
(`git rebase --onto main kpi-compute-fixes`) before opening PR 2. `kpi.rb` is edited in both
PRs, in different methods (the scope in PR 1, `recompute_percentage_change` in PR 2). If a PR would pass its ceiling,
stop and agree the split before adding files.

## 1. Calculated-row marker and fiscal calendar (PR 1)

- [x] 1.1 Make the fiscal calendar in `kpi_cumulative.rb` use `KpiDateUtils` (add `fiscal_year_start` and `fiscal_quarter`
      there); `fiscal_year_key` and `fiscal_quarter_number` have no caller and are removed. Verify by running `kpi_cumulate_mixed_granularity.feature` (E10, E35 fail on the old code).
      The list of portfolio companies and entity settings whose offset differs from the regional default needs production
      data, so it moved to task 8.5 (LLD: Method Contracts, Configuration)
- [x] 1.2 Add the `Kpi.calculated_cumulative` scope (`source = 'auto_cumulation'`, or blank `source` with the legacy
      note prefix) and make `process_cumulative_kpi` stamp the marker. Stamp `source = 'upload'` in
      `KpiWorkbookReader#save_kpi_entry`; make `KpiApprover` copy `source` (blank included) when it overwrites an
      approved row; stamp `source = 'manual'` in `KpisController#create` and `#update`. Verify with a console check of
      a created, an uploaded and an approved-over-calculated row (LLD: File Map)
- [x] 1.3 Write `features/startup/kpi_cumulate_mixed_granularity.feature` scenarios E10, E11 and E35 (fiscal year definition); run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_cumulate_mixed_granularity.feature`
      until green before starting phase 2

## 2. Quarter settling (cumulate) (PR 1)

- [x] 2.1 Add `KpiCumulationPlanner` with `settle_quarters` (pure, BigDecimal) and unit-level checks driven from
      the feature steps; verify the planner file has no ActiveRecord reference (LLD: Method Contracts)
- [x] 2.2 Replace `process_quarterly_cumulatives` in `perform_cumulation` with the planner's quarters and the
      reconciler's upsert. The upsert skips an expected row that already exists and is not calculated (uploaded or
      manual), so an uploaded Quarter stays untouched (E5) from this phase on; it must do so before it calls
      `process_cumulative_kpi`. Verify in task 2.4
- [x] 2.3 Add steps for uploaded Quarter KPIs and for asserting a KPI is absent for a period; let the shared step
      "the following Monthly KPI Reports exist with KPIs:" take optional `notes` and `source` columns. Update the
      existing scenarios that encode the old Quarter rules, noting each behaviour change in the scenario name:
      - `kpi_cumulate.feature` "Only approved KPIs are cumulated" (Jan and Mar approved, Feb not: no Quarter any more)
      - `kpi_cumulate.feature` "Existing cumulative KPI is replaced if value is different" and "... NOT replaced if value
        is the same": seed the Quarter row with the note "Auto-generated Quarter cumulative" so it is a calculated row;
        a row with no marker and no such note is now treated as uploaded and kept (E5, E14)
      - `kpi_extended_aggregation.feature` "Compute KPI using division formula": it builds a Quarter from January alone,
        which is no longer produced; give Revenue and Contribution all three months at the same ratio
      - `kpi_autofill_on_approval_steps.rb` "has an approved cumulated KPI with nil investor_kpi_mapping_id": seed the row
        with the same note, so the "Mapping backfill assigns mapping to cumulated KPIs" scenario still runs on a
        calculated row
- [x] 2.4 Add scenarios H2, E1, E5, E7 (quarter part) to `features/startup/kpi_cumulate_mixed_granularity.feature`
      and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_cumulate_mixed_granularity.feature`,
      then `kpi_cumulate.feature`, `kpi_extended_aggregation.feature` and `kpi_autofill_on_approval.feature` in the same
      folder, until green before starting phase 3

## 3. Year walker (cumulate) (PR 1)

- [x] 3.1 Implement `walk` in the planner: base per quarter, month YTDs while contiguous, quarter total from 3 months
      else the quarter row else stop, Year after Q4, Actual future guard (LLD: Method Contracts)
- [x] 3.2 Wire `perform_cumulation` to plan and reconcile YTD and Year; remove `process_yearly_cumulatives`,
      `process_quarterly_derived_cumulatives` and the `skip_years` logic. Verify with `kpi_cumulate_multi_year.feature`
- [x] 3.3 Check the existing scenarios against the full walk and update any that still expect a partial-quarter YTD
      or Year total, noting the behaviour change in the scenario name. A scan of `kpi_cumulate`,
      `kpi_cumulate_multi_year`, `kpi_autofill_on_approval` and `kpi_extended_aggregation` found none beyond the Quarter
      ones handled in task 2.3 (their data are complete quarters)
- [x] 3.4 Add scenarios H1, H3, H4, H5, H7, E2, E3, E4, E6, E9, E38 to
      `features/startup/kpi_cumulate_mixed_granularity.feature` and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_cumulate_mixed_granularity.feature`
      and `features/startup/kpi_cumulate.feature` and `kpi_cumulate_multi_year.feature` until green before starting phase 4

## 4. Forward fill (PR 1)

- [x] 4.1 Add the `:last` mode to the planner (Quarter = last month only when all 3 months exist; YTD = each month's own
      balance and a Quarter figure's value at a quarter end it alone covers, with no gap stop; Year = Q4 balance only when
      all 4 quarters are covered) and wire `perform_forward_fill`; remove the old forward-fill `process_*` methods.
      Verify with the existing forward-fill scenarios in `kpi_autofill_on_approval.feature`, and change "Forward Fill
      monthly KPIs into Quarterly reports" in `kpi_extended_aggregation.feature` to expect no Quarter for the
      incomplete quarter, noting the behaviour change in the scenario name
- [x] 4.2 Write `features/startup/kpi_forward_fill_mixed_granularity.feature` covering H6, E8, E36 and E39 and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_forward_fill_mixed_granularity.feature`
      until green before starting phase 5

## 5. Reconciler cleanup (PR 1)

- [x] 5.1 Implement stale-row removal in `reconcile_cumulative_kpis` across all fiscal years with source or
      calculated rows (one transaction per KPI, hard delete, log removed periods) and, after the transaction commits, call `cascade_dependent_rag_recompute!`
      for each deleted row when the KPI's mapping has RAG rules. Verify with a console check
- [x] 5.2 In `KpiCumulateJob#perform` take one lock per company (`GET_LOCK` named `kpi_cumulate:<company id>`, ids in
      sorted order, same connection, released in `ensure`; no lock on SQLite) around the run and the inline percentage
      recompute; when still busy after 60 seconds re-queue the job 1 minute later, at most 10 times, then report
      through the existing error notification (LLD: Transactions, Locking and Concurrency)
- [x] 5.3 Write `features/startup/kpi_cumulate_cleanup.feature` covering H8, E12, E13, E14, E30, E34, E37 and X1 and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_cumulate_cleanup.feature`
      until green before starting phase 6

## 6. YTD year-over-year percentage change (PR 2)

- [x] 6.1 In `Kpi.recompute_percentage_change` ([kpi.rb](../../../app/packs/startups/kpis/models/kpi.rb)) group by period, name,
      tag and owner, and compare `YTD` groups with the row at `as_of.prev_year` (month-end matched), nil when missing or
      zero, no fallback; leave Month, Quarter and Year on the previous row. Pick the comparator from the loaded group,
      no query per KPI (LLD: Method Contracts, Queries)
- [x] 6.2 Round a year-over-year change to 2 decimals, then store nil when its absolute value is above 9,999.99
      (decimal(6,2) would overflow), so one extreme figure never aborts the group; cover it with a scenario row in
      task 6.6, including a change of 9,999.995 (LLD: Method Contracts)
- [x] 6.3 Searched `features/` for scenarios that assert a YTD percentage change: none exist. The only percentage-change
      assertions are a Quarter one in `kpi_cumulate.feature` ("Percentage changes are computed over the cumulated KPIs
      in the same run", unaffected: Quarter keeps the previous row), a nil-value one in
      `portfolio_assistant_data_manager.feature`, and job-argument checks in `kpi_autofill_on_approval.feature`. No
      existing scenario needs updating
- [x] 6.4 In `KpisHelper#kpi_percentage_class` return "-" with no colour when `percentage_change` is nil (no threshold
      comparison on nil); print "-" instead of " %" in `kpis/show.html.erb` and `kpis/_kpi.html.erb` (LLD: Method Contracts)
- [x] 6.5 Make `KpiReportsController#recompute_cumulative` pass `compute_percentage_change: true` to `KpiCumulateJob`
      (LLD: Background Jobs)
- [x] 6.6 Write `features/startup/kpi_ytd_yoy_percentage_change.feature` covering H9, E15, E16, E17, E18, E19, E20, E26, E27,
      E31, E32 and E33 with the new percentage-change steps, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_ytd_yoy_percentage_change.feature`
      until green before starting phase 7

## 7. Report fields in the portfolio report (PR 2): Actual against Budget, and fund metrics

- [x] 7.1 In `grid_view_array` ([portfolio_report_doc_generator.rb](../../../app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb))
      replace `kr.kpis.show_in_report.find` with one in-memory index per report of approved KPIs (lower-cased name, first
      match wins); apply the same approved-only index in `PortfolioReportSablonWordService#grid_view_array`; leave the
      KPI screen grid and `KpisHelper#grid_view_array` (no caller in the app) alone; verify approved figures are unchanged with
      `features/fund/portfolio_report.feature` (LLD: Queries and Indexes)
- [x] 7.2 Add the comparator tag constant (`["Budget"]`) and, for each Actual report, the
      `<label>_vs_<tag>_percent` key (Actual ÷ comparator × 100; "N/A" when no report, no KPI, either KPI unapproved, or
      zero); no key for
      Budget, IC or untagged reports; add `data_type` to each row (LLD: Method Contracts)
- [x] 7.3 Write `features/fund/portfolio_report_kpi_vs_budget.feature` covering H10, H11, H12, H15, E21, E22, E23, E24, E25, E28, E29 and E40,
      including a query-count assertion that does not grow with the number of mappings, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_kpi_vs_budget.feature`
      until green
- [x] 7.4 In `add_fund_level_data` ([portfolio_report_doc_generator.rb](../../../app/packs/funds/portfolios/services/portfolio_report_doc_generator.rb))
      add `latest_pi` and `earliest_pi` (latest investment, buy or sale, and first buy across
      all funds, on or before the end date; blank placeholder when none) and `irr` and `moic` on each `<fund>_data` from the stored
      Default-scenario fund ratios (owner the company, latest end date on or before the report's end date, "N/A" when
      never run), one query for all funds (LLD: Method Contracts, Queries and Indexes)
- [x] 7.5 Write `features/fund/portfolio_report_fund_metrics.feature` (steps in
      `features/step_definitions/portfolio_report_fund_metrics_steps.rb`) covering H13, H14 and E41 to E47, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_fund_metrics.feature`
      until green before starting phase 8

## 8. Wrap-up

- [ ] 8.1 Before opening each PR, run `bundle exec rubocop` on its modified files and `bundle exec brakeman`, fix
      findings, and check its file count outside `openspec/` (PR 1 at most 16, PR 2 at most 15)
- [ ] 8.2 Coverage task: list every H/E/X ID in design.md and every ID comment in `features/` and confirm the two
      sets are equal (no ID without a scenario, no scenario without an ID); add any edge case found during apply as
      a new design row and scenario
- [ ] 8.3 PR 1: run every feature that mentions KPIs, not only `kpi_*.feature` (`kpis.feature` and `bulk_query_kpi_*.feature` do not match
      that name): `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber $(grep -rli kpi features --include='*.feature')` until green. PR 2: run the
      same plus `features/fund/portfolio_report.feature features/fund/portfolio_report_kpi_vs_budget.feature features/fund/portfolio_report_fund_metrics.feature` until green
- [ ] 8.4 Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off (for QA, not for the
      apply agent)
- [ ] 8.5 Before the PR 1 deploy, list the companies and entity settings whose fiscal start differs from the regional default
      (ops, on production: `Investor.where(category: "Portfolio Company")` whose `json_fields["month_offset_for_fy"]` is present and not
      `EntitySetting.geo_default_month_offset_for_fy`, and `EntitySetting` rows whose `month_offset_for_fy` is set and differs); their
      fiscal years shift. After the PR 1 deploy (ops, not the apply agent): recompute cumulation for the test investor first, then the
      others; do those companies deliberately and check their Year and YTD columns.
      After the PR 2 deploy: run the percentage-change recompute per company, test investor first, to correct
      stored YTD changes (LLD: Configuration and Rollout)
