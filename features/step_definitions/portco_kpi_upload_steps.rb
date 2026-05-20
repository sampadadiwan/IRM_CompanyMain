

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

When('I visit the KPI report edit page via a signed link for user {string} and report {string}') do |first_name, report_args|
  portco_user = User.find_by(first_name: first_name)
  as_of_val = report_args.split(";").map { |p| p.split("=") }.to_h["as_of"]
  portco = Investor.find_by(investor_name: "MyStartup")
  @kpi_report = KpiReport.find_by(as_of: as_of_val, portfolio_company_id: portco.id)
  signed_id = KpiReport.signed_id_for_user(@kpi_report, portco_user)
  visit(edit_kpi_report_path(id: :shared, signed_id: signed_id))
end

Then('I should see the KPI report form') do
  expect(page).to have_content("KPI Report")
end

When('I visit the KPI report edit page via an expired signed link') do
  # Generate a token that expired immediately
  verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
  expired_token = verifier.generate(
    { record_id: @kpi_report.id, email: "any@example.com", model: "KpiReport" },
    expires_in: -1.second,
    purpose: :shared_access
  )
  visit(edit_kpi_report_path(id: :shared, signed_id: expired_token))
end

