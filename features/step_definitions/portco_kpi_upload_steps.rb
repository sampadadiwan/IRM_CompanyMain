

Given('a KpiReport {string} exists for the portfolio company {string}') do |report_args, portco_name|
  portco = Investor.find_by(investor_name: portco_name)

  # Create a fund user to own the pre-created report
  fund_user = FactoryBot.create(:user, entity: @entity)

  @kpi_report = KpiReport.new(
    entity: @entity,
    portfolio_company: portco,
    user: fund_user,
    enable_portco_upload: true,
    tag_list: "Actual"
  )
  key_values(@kpi_report, report_args)
  @kpi_report.save!(validate: false)
end

When('I fill out the KPI report {string} for portfolio company {string} with notes {string}') do |as_of_val, portco_name, notes|
  portco = Investor.find_by(investor_name: portco_name)
  report = KpiReport.find_by(as_of: as_of_val, portfolio_company_id: portco.id)
  visit(edit_kpi_report_path(report))
  expect(page).to have_content("KPI Report")
  fill_in("Notes", with: notes)
  click_on("Save")
  expect(page).to have_content("Kpi report was successfully updated.")
end

Then('the KPI report should have notes {string}') do |expected_notes|
  @kpi_report.reload
  expect(@kpi_report.notes).to eq(expected_notes)
end

Then('the KPI report should be owned by user {string}') do |first_name|
  @kpi_report.reload
  expect(@kpi_report.user.first_name).to eq(first_name)
end
