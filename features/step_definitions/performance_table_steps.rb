# Steps for features/startup/kpi_performance_table_change.feature. They call the service directly: the rows are what the
# performance table page colours and prints. The service's monthly scope compares the period with 'month', which MySQL
# matches whatever the case but the SQLite test database does not, so the reports are made with that spelling.

When('the performance table is built as of {string}') do |as_of|
  as_of = Date.parse(as_of)
  kpi_report = KpiReport.find_by!(entity: @entity, portfolio_company_id: @portfolio_company.id, period: 'month', as_of:)
  @performance_rows = PerformanceTableService.call(kpi_report:, portfolio_company_id: @portfolio_company.id, metric_names: nil, as_of:)
end

def performance_row(name)
  row = @performance_rows.find { |candidate| candidate.metric == name }
  expect(row).to be_present, "no performance table row for #{name}"
  row
end

Then('the performance table row {string} should have a {word} of {float}') do |name, field, expected|
  expect(performance_row(name)[field].round(2)).to eq(expected)
end

Then('the performance table row {string} should have an empty {word}') do |name, field|
  expect(performance_row(name)[field]).to be_nil
end
