# Steps for features/fund/portfolio_report_kpi_category.feature and features/fund/portfolio_report_fund_total_gross_irr.feature.
# The KPI ones call the report's KPI rows directly (see portfolio_report_kpi_steps.rb), as the rows are what the Word template reads.

# An empty string clears the category
Given('the {string} KPI mapping has category {string}') do |name, category|
  InvestorKpiMapping.find_by!(standard_kpi_name: name, entity: @entity, investor: @portfolio_company).update!(category:)
end

# The all-KPIs list and each category's own list come from the same builder, called with the category
When('the portfolio report rows for the {string} category are built up to {string}') do |category, end_date|
  @report_rows = PortfolioReportDocGenerator.allocate.send(:grid_view_array, @portfolio_company, Date.parse(end_date), category:)
end

Then('the report row {string} should have category {string}') do |name, expected|
  expect(report_row(name).category).to eq(expected)
end

Then('the report has no row {string}') do |name|
  expect(@report_rows.map(&:header)).not_to include(name)
end

# ── Fund totals and company fund lines (features/fund/portfolio_report_fund_total_gross_irr.feature) ─────────────────────

# A ratio of a second fund set up by 'a second fund {string} that only Company D invests in...'
Given('the fund {string} has a {string} ratio of {float} on {string}') do |fund_name, name, value, date|
  fund = Fund.find_by!(name: fund_name)
  FactoryBot.create(:fund_ratio, entity: fund.entity, fund:, owner: fund, name:, value:, end_date: Date.parse(date))
end

# The company's own IRR in the fund (owner is the company), not the fund's
Given('{string} has an IRR of {float} in the Inflexor fund on {string}') do |company_name, value, date|
  company = Investor.find_by!(investor_name: company_name)
  FactoryBot.create(:fund_ratio, entity: @fund.entity, fund: @fund, owner: company, name: "IRR", value:, end_date: Date.parse(date))
end

# The plain step reads "N/A".to_d as 0, so a zero needs to be told apart from a missing value
Then('the total of {string} shows {word} {string} as a number') do |fund_name, field, expected|
  value = fund_total_named(fund_name).public_send(field)
  expect(value).to be_a(Numeric), "#{field} was #{value.inspect}"
  expect(value.to_d).to be_within(0.05).of(expected.to_d)
end

Then('the line of {string} has no {word} field') do |name, field|
  expect(fund_metrics_line(name)).not_to respond_to(field)
end
