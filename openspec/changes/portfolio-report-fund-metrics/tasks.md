# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Setup for every run:** Redis up on 6379 and a fresh `TEST_ENV_NUMBER=$RANDOM` on each cucumber
> run. Worked-example IDs are in [design.md](design.md#worked-examples); LLD sections are in
> [lld.md](lld.md). Every scenario has a comment line naming its ID and path, and code comments name
> the IDs of the paths they implement.

## 1. Holdings at a date and report dates

- [x] 1.1 Add `PortfolioInvestmentsAsOf` (LLD Method Contracts) taking a relation and a `Date`, refusing a loaded relation
- [x] 1.2 Coerce start and end to `Date` once in `PortfolioReportConsolidatedDocGenerator` and add `prior_day` and the per-fund `financial_year_day` through `KpiDateUtils` (LLD Method Contracts, Value rules)
- [x] 1.3 Write `features/fund/portfolio_report_holdings_at_dates.feature` and `features/step_definitions/portfolio_report_quarter_metrics_steps.rb` (shared setup) covering X1, X2, X3 (traceability comments on each), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_holdings_at_dates.feature`
      until green before starting phase 2

## 2. Fund money as of a date

- [x] 2.1 Add the money figures to `FundAsOf` (LLD Method Contracts, FundAsOf table): committed, call, collected (verified remittances' payments), distribution, total units premium, the tracking versions, and the undated target; verify the capital call and distribution letters that use `FundAsOf` still generate
- [x] 2.2 Write `features/fund/fund_as_of_amounts.feature` covering H18, E27–E31, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/fund_as_of_amounts.feature`
      until green before starting phase 3; also re-run the existing capital remittance and capital distribution document features

## 3. Consolidated company fund lines

- [x] 3.1 Replace the `OpenStruct` in `add_funds` with `FundLine` and `Ratio` (`Data.define`, field list in LLD Method Contracts) and keep every existing field's value; verify by running the existing scenarios of `features/fund/consolidated_portfolio_report.feature`
- [x] 3.2 Add the fund money and tracking figures (from `fund.as_of(@end_date)`), `cost_of_investment_prior`, `_between`, `cost_of_remaining`, `cost_of_remaining_prior`, `cost_of_sold_between` (positive), `fmv_prior`, `fmv_change_percent`, `fmv_fy_start` and `fmv_fy_start_change_percent`, valued through the helper (LLD Queries and Indexes); verify against the proposal's roll-forward numbers
- [x] 3.3 Update the class header comment of `PortfolioReportConsolidatedDocGenerator` to list the new fields
- [x] 3.4 Write `features/fund/portfolio_report_company_fund_lines.feature` covering H1–H8, E1–E14, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_company_fund_lines.feature`
      until green before starting phase 4; also re-run `features/fund/consolidated_portfolio_report.feature`

## 4. Fund totals

- [x] 4.1 Replace the `OpenStruct` in `fund_totals` with `FundTotal` (`custom_fields` stays `OpenStruct`); money copied once from the fund, never summed
- [x] 4.2 Sum the cost and value fields, derive `fmv_change_percent` from the sums, add `collected_percent`, `uncollected_amount`, `uncollected_percent` and `company_count`; verify against the proposal's Total row (70 / 10 / 5 / 75 and 74 / 81 / 9.5)
- [x] 4.3 Read `irr` (XIRR), `moic`, `tvpi`, `dpi`, `rvpi` with one `FundRatio` query for all funds (LLD Queries and Indexes); "N/A" when absent; verify with TVPI runs before and after the end date
- [x] 4.4 Write `features/fund/portfolio_report_fund_totals.feature` covering H9–H13, E15–E22, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_fund_totals.feature`
      until green before starting phase 5

## 5. Company page fund data

- [x] 5.1 In `PortfolioReportDocGenerator#add_fund_level_data` value the fund's PIs through the helper and add `sold_amount` (sum of sells' `amount_cents`, positive) and `cost_of_remaining`; verify existing fields are unchanged
- [x] 5.2 Write `features/fund/portfolio_report_company_fund_data.feature` covering H14, H15, E23, E24, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_company_fund_data.feature`
      until green before starting phase 6

## 6. KPI variance

- [x] 6.1 Add `variance_of` and write `"<label>_vs_budget_compute_percent"` beside the existing percent in the comparator loop of `grid_view_array`; verify the existing `_vs_budget_percent` rows are unchanged
- [x] 6.2 Write `features/fund/portfolio_report_kpi_budget_variance.feature` (its own file, as `portfolio_report_kpi_vs_budget.feature` already uses E25 for another scenario) covering H16, H17, E25, E26, and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_kpi_budget_variance.feature`
      until green before starting phase 7

## 7. Wrap-up

- [x] 7.1 Run `bundle exec rubocop` on the modified files and `bundle exec brakeman` (no controller change expected) and fix findings
- [x] 7.2 Run all the features of phases 1–6 together, plus `features/fund/consolidated_portfolio_report.feature`, with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber <the six feature files>` and confirm green
- [x] 7.3 Coverage check: list every H/E/X ID in design.md and every ID comment in `features/` and confirm the two sets are equal; any edge case found during apply gets a design.md row and a scenario
- [x] 7.4 Confirm the three Word templates in `public/final_portfolio_report_docs/` use the field names of the spec (`cost_of_remaining_prior`, `cost_of_remaining`, `fmv_change_percent`, `fmv_fy_start`, `fmv_fy_start_change_percent`, `sold_amount`, `_vs_budget_compute_percent`)
- [ ] 7.5 Run qa-checklist.md on a deployed build and record the sign-off (for QA, not the apply agent)
