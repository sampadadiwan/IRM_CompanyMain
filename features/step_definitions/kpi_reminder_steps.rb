
Given('{string} has a user with email {string}') do |portco_name, email|
  @portfolio_company = Investor.find_by(investor_name: portco_name)
  user = FactoryBot.create(:user, email: email, entity: @portfolio_company.investor_entity)
end

Given('the entity setting for {string} has kpi_reminder_frequency {string} and kpi_reminder_before {int}') do |_fund_name, frequency, before|
  @entity.entity_setting.update!(
    kpi_reminder_frequency: frequency,
    kpi_reminder_before: 0 # Force trigger today
  )
  @entity.permissions.set(:enable_kpis)
  @entity.permissions.set(:enable_investors)
  @entity.save!
  @user.permissions.set(:enable_kpis)
  @user.permissions.set(:enable_investors)
  @user.save!

  # Stub calculate_target_date to return today
  allow_any_instance_of(GeneratePeriodicKpiReportsJob).to receive(:calculate_target_date).and_return(Time.zone.today)
end

When('the periodic KPI report generation job runs for today') do
  puts "Entity ID: #{@entity.id}"
  puts "Entity name: #{@entity.name}"
  puts "Enable KPIs: #{@entity.permissions.enable_kpis?}"
  puts "Frequency: #{@entity.entity_setting.kpi_reminder_frequency}"
  puts "Trigger date: #{Time.zone.today.end_of_month - (@entity.entity_setting.kpi_reminder_before || 0).days}"
  puts "Today: #{Time.zone.today}"
  puts "Investors count: #{@entity.investors.count}"
  puts "Portfolio Companies count: #{@entity.investors.portfolio_companies.count}"

  GeneratePeriodicKpiReportsJob.new.perform

  puts "KpiReports count: #{KpiReport.count}"
  puts "Notifications count: #{Noticed::Notification.count}"
end

Then('an email should be sent to {string} with subject containing {string}') do |email, subject|
  # Using capybara-email DSL
  open_email(email)
  expect(current_email.subject).to include(subject)
end

And('the email should contain a link to {string}') do |link_text|
  expect(current_email).to have_link(link_text)
end

When('I follow the {string} link in the email') do |link_text|
  current_email.click_link(link_text)
end

Then('I should see the kpi report details') do
  @kpi_report = KpiReport.last
  expect(page).to have_content(@kpi_report.portfolio_company.investor_name)
  localized_date = I18n.l(@kpi_report.as_of)
  iso_date = @kpi_report.as_of.strftime("%Y-%m-%d")
  expect(page).to have_content(/#{Regexp.escape(localized_date)}|#{Regexp.escape(iso_date)}/)
end

When('I press {string}') do |button_text|
  click_on button_text
  click_on "Proceed" if button_text == "Send Notification"
  sleep(2)
end

Given('I am on the kpis page for the portfolio company {string}') do |portco_name|
  @portfolio_company = Investor.find_by(investor_name: portco_name)
  visit kpi_reports_path(portfolio_company_id: @portfolio_company.id, grid_view: true)
end

Given('I revoke investor access in the portfolio company {string}') do |portco_name|
  @portfolio_company = Investor.find_by(investor_name: portco_name)
  InvestorAccess.where(investor_id: @portfolio_company.id).delete_all
end

When('I click the dropdown item {string}') do |dropdown_name|
  click_on dropdown_name
end

Then('I should see a modal with title {string}') do |title|
  expect(page).to have_css(".modal", visible: true)
  expect(page).to have_content(title)
end


Then('a KpiReport {string} should exist for the portfolio company {string}') do |args, portco_name|
  portfolio_company = Investor.find_by(investor_name: portco_name)
  kpi_report = KpiReport.where(portfolio_company_id: portfolio_company.id).last
  expect(kpi_report).not_to be_nil
  key_values(kpi_report, args)
end

# Send Reminder redirects to the report it created — the report's own page, not the grid it was sent from
Then('I am on the KPI report for {string} as of {string}') do |portco_name, as_of|
  portfolio_company = Investor.find_by!(investor_name: portco_name)
  kpi_report = KpiReport.find_by!(portfolio_company_id: portfolio_company.id, as_of: Date.parse(as_of))
  expect(page).to have_current_path(kpi_report_path(kpi_report))
end

# No reminder modal (or its backdrop) is left open over the page
Then('the KPI reminder modal is closed') do
  expect(page).to have_no_css(".modal.show")
  expect(page).to have_no_css(".modal-backdrop")
end

# The greyed-out dropdown entry: disabled, no modal behind it, and the reason on its tooltip wrapper
Then('Send Reminder is disabled saying {string}') do |message|
  link = find("#kpi_send_reminder_link.disabled", text: "Send Reminder")
  expect(link['data-bs-toggle']).to be_nil
  # Bootstrap moves title to data-bs-original-title once the tooltip initialises
  wrapper = link.find(:xpath, "..")
  expect(wrapper[:title].presence || wrapper['data-bs-original-title']).to include(message)
  expect(page).to have_no_css("[id^='sendReminderModal-']", visible: :all)
end
