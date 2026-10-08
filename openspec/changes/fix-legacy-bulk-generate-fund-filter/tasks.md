# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

## 1. Fix the fund filter

- [x] 1.1 In `legacy_bulk_generate` (portfolio_reports_controller.rb, LLD File Map), replace the `joins(:portfolio_investments)...distinct` fund filter with `where(id: PortfolioInvestment.where(fund_id: fund_ids).select(:portfolio_company_id))`. Verify `git diff` shows only that line changed and `@portfolio_companies` still has `order(:investor_name)`. (LLD: Queries and Indexes)
- [x] 1.2 Confirm an index exists on `portfolio_investments` for `fund_id` or `portfolio_company_id` in `db/schema.rb`; note the result in the PR. (LLD: Queries and Indexes)
- [x] 1.3 Grep for other `.distinct` on ordered investor relations (e.g. `rg "joins\(.*\).*distinct" app/packs/funds/portfolios`) and list any hits in the PR rather than fixing them here. (Design: Open Question 1)
- [ ] 1.4 Add steps to `features/step_definitions/bulk_portfolio_report.rb` for previewing by fund/sector and asserting which companies are selected, then write the Fund-filter scenarios in `features/fund/bulk_portfolio_report.feature` covering H1, H2, E1, E2, E3. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/bulk_portfolio_report.feature` and confirm it passes. Run `bundle exec rubocop app/packs/funds/portfolios/controllers/portfolio_reports_controller.rb` clean.

## 2. Verify on MySQL

- [ ] 2.1 After deploy to dev, load `/portfolio_reports/legacy_bulk_generate?previewed=true&fund_ids[]=11` and confirm no error (X1). Run `qa-checklist.md` on the deployed build and record the sign-off (for QA, not the apply agent).
