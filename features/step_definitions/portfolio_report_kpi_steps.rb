# Steps for features/fund/portfolio_report_kpi_vs_budget.feature. They call the report's KPI rows directly: the rows
# are what the Word template reads, and building a whole .docx adds nothing to what is checked here.

Given('the {string} KPI mapping is shown in the portfolio report') do |name|
  InvestorKpiMapping.find_by!(standard_kpi_name: name, entity: @entity, investor: @portfolio_company).update!(show_in_report: true)
end

Given('the {string} KPI mapping has data type {string}') do |name, data_type|
  InvestorKpiMapping.find_by!(standard_kpi_name: name, entity: @entity, investor: @portfolio_company).update!(data_type:)
end

# The generator's initialize builds a whole document, so only the row building is called
When('the portfolio report rows are built up to {string}') do |end_date|
  @report_rows = PortfolioReportDocGenerator.allocate.send(:grid_view_array, @portfolio_company, Date.parse(end_date))
end

# The AI-drafted report's Word export mirrors the same rows (labels are not underscored there)
When('the AI-drafted report rows are built up to {string}') do |end_date|
  service = PortfolioReportSablonWordService.allocate
  service.instance_variable_set(:@portco, @portfolio_company)
  service.instance_variable_set(:@end_date, Date.parse(end_date))
  @report_rows = service.send(:grid_view_array)
end

def report_row(name)
  row = @report_rows.find { |candidate| candidate.header == name }
  expect(row).to be_present, "no report row for #{name}"
  row
end

# "N/A" or a number
Then('the report row {string} should have {string} equal to {string}') do |name, field, expected|
  value = report_row(name)[field]
  expected == 'N/A' ? expect(value).to(eq('N/A')) : expect(value.to_f).to(eq(expected.to_f))
end

Then('the report row {string} should have no {string} field') do |name, field|
  expect(report_row(name).to_h).not_to have_key(field.to_sym)
end

Then('the report row {string} should have data type {string}') do |name, expected|
  expect(report_row(name).data_type).to eq(expected)
end
