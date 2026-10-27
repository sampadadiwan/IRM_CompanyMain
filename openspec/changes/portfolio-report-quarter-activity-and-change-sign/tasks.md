# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Setup for every run:** Redis up on 6379 and a fresh `TEST_ENV_NUMBER=$RANDOM` on each cucumber
> run. Worked-example IDs are in [design.md](design.md#worked-examples); LLD sections are in
> [lld.md](lld.md). Every scenario has a comment line naming its ID and path, and code comments name
> the IDs of the paths they implement.

> **Scope:** the quarter fields on each fund's data in the company report; the corrected direction of a change from a
> negative figure and percentage points for percentage KPIs (stored KPI change, the report's budget difference); and the
> per-unit basis for the consolidated fair market value change. More report changes may be added to this bundle before the
> build; add each as its own phase.

## 1. Quarter activity in the company report

- [x] 1.1 Confirm `features/fund/portfolio_report_company_quarter_activity.feature` and `features/step_definitions/portfolio_report_quarter_change_steps.rb` do not exist yet (LLD File Map); the Write tool replaces files silently
- [x] 1.2 In `PortfolioReportDocGenerator#add_fund_level_data` rename `_start_date` to `start_date`, convert it with `to_date`, split `buys` and `sells` into the period (dated on or after the start date), and add `buy_pis_present`, `sell_pis_present`, `cost_of_investment_between` and `cost_of_sold_between` to the struct beside `cost_of_investment`; add a code comment naming H1–H6, E1–E10, X1 (LLD Method Contracts)
- [x] 1.3 Add the quarter steps to `features/step_definitions/portfolio_report_quarter_change_steps.rb` (LLD Test Plumbing), including the text-dates step for X1
- [x] 1.4 Write `features/fund/portfolio_report_company_quarter_activity.feature` covering H1–H6, E1–E10 and X1 (a comment above each scenario names its ID and path; the header links to design.md#worked-examples), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_company_quarter_activity.feature`
      until green before starting phase 2; also re-run `features/fund/portfolio_report_company_fund_data.feature` and `features/fund/portfolio_report_company_fund_lines.feature` to confirm the existing fund data is unchanged

## 2. Change direction for KPI changes

- [x] 2.1 In `Kpi.change_against` divide by `comparator.value.abs`; for a percentage KPI (`kpi.investor_kpi_mapping&.percentage?`) return `(kpi.value - comparator.value) * 100` before the zero guard; update its comment; add `:investor_kpi_mapping` to the `preload` in `KpiPercentageChangeJob`; name H7–H14, E11–E16, E22–E24, E33 in a code comment (LLD Method Contracts); confirm `year_over_year_change` and `PERCENTAGE_CHANGE_LIMIT` need no edit
- [x] 2.2 Write `features/startup/kpi_change_direction.feature` covering H7–H14, E11–E16, E22–E24 and E33 (reuse the KPI steps in LLD Test Plumbing; add the "shows in red in the grid" step; set `data type "percentage"` on the EBITDA % mapping with the existing step), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/startup/kpi_change_direction.feature`
      until green; also re-run `features/startup/kpi_ytd_yoy_percentage_change.feature`, `features/startup/kpi_cumulate.feature` and `features/startup/kpi_autofill_on_approval.feature` to confirm the positive-base changes are unchanged

## 3. Budget difference and fair market value change

- [x] 3.1 In `PortfolioReportDocGenerator#variance_of` keep the guard for a missing KPI or comparator and return `Kpi.change_against(comparator, kpi)`, with "N/A" when it is nil (the zero-comparator guard now lives in `change_against`); leave `percent_of` alone
- [x] 3.2 In `PortfolioReportConsolidatedDocGenerator#change_percent` divide by `base.to_d.abs`
- [x] 3.3 Write `features/fund/portfolio_report_change_direction.feature` covering H15–H18 and E17–E21 (add the two fair market value steps from LLD Test Plumbing), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_change_direction.feature`
      until green; also re-run `features/fund/portfolio_report_kpi_budget_variance.feature`, `features/fund/portfolio_report_kpi_vs_budget.feature` and `features/fund/portfolio_report_fund_totals.feature`

## 4. Per-unit fair market value change

- [x] 4.1 Confirm `features/fund/portfolio_report_fmv_per_unit_change.feature` does not exist yet, and spike first: write H19 only (10 units at 100, 5 bought, 110 at the end) and prove a frozen prior-list buy's `net_quantity` is the quantity at its date before building on it (LLD reviewer check); if it is not, stop and update the design
- [x] 4.2 In `PortfolioReportConsolidatedDocGenerator` add `fmv_at_prior_quantity` and `fmv_at_fy_start_quantity` to `FundLine`, `fmv_at_prior_quantity` to `FundTotal` and `FUND_LINE_SUMS`, and the two private helpers `unit_values_at_end` and `value_at_unit_values` (LLD Method Contracts); fill the fields in `fund_line`, work `fmv_change_percent` and `fmv_fy_start_change_percent` from them and `fund_total`'s percent from the sums; leave `fmv`, `fmv_prior`, `fmv_fy_start` as they are; name H19–H24, E25–E32 in a code comment
- [x] 4.3 Write `features/fund/portfolio_report_fmv_per_unit_change.feature` covering H19–H24 and E25–E32 (steps in LLD Test Plumbing), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_fmv_per_unit_change.feature`
      until green; also re-run `features/fund/portfolio_report_fund_totals.feature`, `features/fund/portfolio_report_company_fund_lines.feature`, `features/fund/portfolio_report_fund_metrics.feature` and `features/fund/consolidated_portfolio_report.feature`, and confirm their fair market value change cases keep their values (no units change in their data)

## 5. Wrap-up

- [x] 5.1 Run `bundle exec rubocop` on the modified files and the new steps file, and fix findings; `bundle exec brakeman` is not needed (no controller or data-handling change)
- [x] 5.2 Run the related features together to confirm nothing regressed:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_company_quarter_activity.feature features/startup/kpi_change_direction.feature features/fund/portfolio_report_change_direction.feature features/fund/portfolio_report_fmv_per_unit_change.feature features/fund/portfolio_report_company_fund_data.feature features/fund/portfolio_report_company_fund_lines.feature features/fund/portfolio_report_kpi_budget_variance.feature features/startup/kpi_ytd_yoy_percentage_change.feature features/startup/kpi_cumulate.feature features/fund/portfolio_report_fund_totals.feature features/fund/consolidated_portfolio_report.feature`
- [x] 5.3 Coverage check: list every H/E/X ID in design.md and every ID comment in the four new features and confirm the two sets are equal; any edge case found during apply gets a design.md row and a scenario, never a scenario alone
- [ ] 5.4 Tell the template authors the four new merge fields and how to use them: a condition on `buy_pis_present` and the field `cost_of_investment_between`, a condition on `sell_pis_present` and `cost_of_sold_between`, inside each fund's block of the company template; the sample templates in `public/final_portfolio_report_docs/` are not changed here
- [ ] 5.5 Rollout (for the release owner, not the apply agent): after deploy, run "Recompute percentage change" for each company with negative KPI figures or percentage KPIs, tell KPI owners that thresholds on percentage KPIs are now held against points, then generate reports (LLD Configuration and Rollout)
- [ ] 5.6 Run qa-checklist.md on a deployed build and record the sign-off (for QA, not the apply agent)
