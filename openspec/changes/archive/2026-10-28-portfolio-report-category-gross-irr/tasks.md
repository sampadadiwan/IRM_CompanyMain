# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Setup for every run:** Redis up on 6379 and a fresh `TEST_ENV_NUMBER=$RANDOM` on each cucumber
> run. Worked-example IDs are in [design.md](design.md#worked-examples); LLD sections are in
> [lld.md](lld.md). Every scenario has a comment line naming its ID and path, and code comments name
> the IDs of the paths they implement.

> **Scope:** `category` on the KPI row and `gross_portfolio_irr` on the consolidated fund total, each company's fund line and the company report's fund data. The per-share FMV
> change percent is deferred (see the open decision in
> [portfolio-report-fund-metrics design](../archive/2026-10-27-portfolio-report-fund-metrics/design.md#open-decision-per-share-basis-for-fmv-change-percent)) and is not a task here.

## 1. KPI row category

- [x] 1.1 Confirm `features/fund/portfolio_report_kpi_category.feature` and `features/step_definitions/portfolio_report_category_gross_irr_steps.rb` do not exist yet (LLD File Map); the Write tool replaces files silently
- [x] 1.2 In `PortfolioReportDocGenerator#grid_view_array` add `"category" => ikm.category.to_s` to `row_data` beside `"data_type"`, extend the comment above it, and name H1–H3, E1, E2 in a code comment (LLD Method Contracts); verify by building the rows for a company with a categorised mapping and reading the row's `category`
- [x] 1.3 Write `features/fund/portfolio_report_kpi_category.feature` with the three category steps from LLD Test Plumbing in `features/step_definitions/portfolio_report_category_gross_irr_steps.rb`, covering H1, H2, H3, E1, E2 (a comment above each scenario names its ID and path; the header links to design.md#worked-examples), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_kpi_category.feature`
      until green before starting phase 2; also re-run `features/fund/portfolio_report_kpi_vs_budget.feature` and `features/fund/portfolio_report_kpi_budget_variance.feature` to confirm the existing row fields are unchanged

## 2. Gross Portfolio IRR on the fund total

- [x] 2.1 In `PortfolioReportConsolidatedDocGenerator` add `:gross_portfolio_irr` to `FundTotal` beside `:irr` and `gross_portfolio_irr: "Gross Portfolio IRR"` to `FUND_RETURN_RATIOS`; update the header comment's list of returns and name H4–H6, E3–E11 in a code comment (LLD Method Contracts); verify the existing `fund_total` still builds without change and `FundLine` is untouched
- [x] 2.2 Add the step `the line of {string} has no {word} field` to `features/step_definitions/portfolio_report_category_gross_irr_steps.rb` (LLD Test Plumbing)
- [x] 2.3 Write `features/fund/portfolio_report_fund_total_gross_irr.feature` covering H4, H5, H6, H7, E3, E4, E5, E6, E7, E8, E9, E10, E11 (comment above each scenario; header links to design.md#worked-examples; reuse `the fund has a {string} ratio of {float} on {string}` and `the total of {string} shows {word} {string}`), and run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_fund_total_gross_irr.feature`
      until green before starting phase 3

## 3. Wrap-up

- [x] 3.1 Run `bundle exec rubocop` on the two modified services and the new steps file, and fix findings; `bundle exec brakeman` is not needed (no controller or data-handling change)
- [x] 3.2 Run the related features together to confirm nothing regressed:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/portfolio_report_kpi_category.feature features/fund/portfolio_report_fund_total_gross_irr.feature features/fund/portfolio_report_fund_totals.feature features/fund/portfolio_report_company_fund_lines.feature features/fund/consolidated_portfolio_report.feature`
- [x] 3.3 Coverage check: list every H/E/X ID in design.md and every ID comment in the two new features and confirm the two sets are equal; any edge case found during apply gets a design.md row and a scenario, never a scenario alone
- [x] 3.4 Tell the template authors the two new mail merge fields: `=kpi.category` inside the KPI loop (`kpis:each(kpi)`) and `=total.gross_portfolio_irr` inside the fund totals loop (`fund_totals:each(total)`), not inside the company then fund loop; the sample templates in `public/final_portfolio_report_docs/` are not changed here
- [x] 3.5 Run qa-checklist.md on a deployed build and record the sign-off (for QA, not the apply agent)
