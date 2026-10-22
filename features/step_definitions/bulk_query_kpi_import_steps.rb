# Steps for features/startup/bulk_query_kpi_import.feature (bulk-path-query-optimisation, phase 4).
# Setup and the import itself reuse kpi_workbook_steps.rb ("the KPI workbook file {string} for a kpi report",
# "the target KPIs are {string}", "the KpiWorkbookReader processes the file"); counts use query_budget_steps.rb.

# E2: what one import left, to compare with a second import of the same workbook
Given('I note the staged KPIs of the portfolio company') do
  @staged_kpi_ids = Kpi.unapproved.where(portfolio_company_id: @portfolio_company.id).order(:id).pluck(:id)
  expect(@staged_kpi_ids).not_to be_empty
end

# E2: re-importing updates the KPIs the first import created - same rows, none added
Then('the staged KPIs of the portfolio company should be the same rows') do
  expect(Kpi.unapproved.where(portfolio_company_id: @portfolio_company.id).order(:id).pluck(:id)).to eq(@staged_kpi_ids)
end

# E2: never two staged KPIs for the same report, name and mapping
Then('no staged KPI of the portfolio company should be duplicated') do
  duplicates = Kpi.unapproved.where(portfolio_company_id: @portfolio_company.id)
                  .group(:kpi_report_id, :name, :investor_kpi_mapping_id).having("COUNT(*) > 1").count
  expect(duplicates).to be_empty, "duplicated staged KPIs: #{duplicates.inspect}"
end
