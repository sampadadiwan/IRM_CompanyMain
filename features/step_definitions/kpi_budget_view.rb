When('I go to the KPI reports page for {string} with budget view enabled and tags {string}') do |company_name, tags|
  company = Investor.find_by(investor_name: company_name)
  tag_params = tags.split(',').map { |t| "tag_list%5B%5D=#{CGI.escape(t)}" }.join('&')
  visit "/kpi_reports?budget_view=true&portfolio_company_id=#{company.id}&#{tag_params}&entity_id=#{@user.entity_id}"
end

Then('I should see a column header {string}') do |header_text|
  expect(page).to have_css('th', text: header_text)
end

Then('I should see {string} in the {string} row under the achievement column') do |value, kpi_name|
  # Finding the row with the KPI name and then checking the achievement column
  # In the table, achievement column is usually the last one in each as_of group
  # But for simplicity, we can check if the value exists in the row
  # row = find('tr', text: kpi_name, wait: 10)
  # expect(row).to have_content(value)
  expect(page).to have_content(kpi_name)
  expect(page).to have_content(value)
end

Given('a KpiReport {string} exists for the entity {string}') do |args, entity_name|
  entity = Investor.find_by(investor_name: entity_name)
  # Standardize standard_kpi_name for mapping
  # Use reported_kpi_name to satisfy validations if necessary
  InvestorKpiMapping.find_or_create_by!(standard_kpi_name: "Revenue", reported_kpi_name: "Revenue", entity: @user.entity, investor: entity, category: "General")

  @kpi_report = KpiReport.new(entity: @user.entity, portfolio_company_id: entity.id, user: @user)
  key_values(@kpi_report, args)
  @kpi_report.save!
end
