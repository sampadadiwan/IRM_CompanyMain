
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
  @entity.save!

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
  expect(page).to have_content(I18n.l(@kpi_report.as_of))
  expect(page).to have_content(@kpi_report.entity.name)
  
end


