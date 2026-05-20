# Steps for: features/startup/portco_kpi_workflow.feature

# ─────────────────────────────────────────────────────────────────────────────
# DATA SETUP
# ─────────────────────────────────────────────────────────────────────────────

Given('the fund entity has KPIs enabled') do
  @entity.update!(enable_kpis: true)
  @user.permissions.set(:enable_kpis)
  @user.save!
  @entity.entity_setting.update!(from_email: 'fund@example.com', sandbox: false)
end

Given('the portfolio company has an approved portco user {string}') do |name_kv|
  portco = @portfolio_company || Investor.find_by!(investor_name: 'TestStartup')
  @portco_user = FactoryBot.build(:user, entity: portco.investor_entity)
  key_values(@portco_user, name_kv)
  @portco_user.save!
  @portco_user.add_role(:company_admin)
  InvestorAccess.create!(
    investor: portco,
    user: @portco_user,
    entity_id: portco.entity_id,
    first_name: @portco_user.first_name,
    last_name: @portco_user.last_name,
    email: @portco_user.email,
    approved: true
  )
end

Given('the portfolio company {string} has an approved portco user {string}') do |portco_name, name_kv|
  portco = Investor.find_by!(investor_name: portco_name)
  user = FactoryBot.build(:user, entity: portco.investor_entity)
  key_values(user, name_kv)
  user.save!
  user.add_role(:company_admin)
  InvestorAccess.create!(
    investor: portco,
    user: user,
    entity_id: portco.entity_id,
    first_name: user.first_name,
    last_name: user.last_name,
    email: user.email,
    approved: true
  )
  @other_portco_user = user
  @other_portfolio_company = portco
end

Given('the portfolio company has a second approved portco user {string}') do |name_kv|
  portco = @portfolio_company || Investor.find_by!(investor_name: 'TestStartup')
  @second_portco_user = FactoryBot.build(:user, entity: portco.investor_entity)
  key_values(@second_portco_user, name_kv)
  @second_portco_user.save!
  @second_portco_user.add_role(:company_admin)
  InvestorAccess.create!(
    investor: portco,
    user: @second_portco_user,
    entity_id: portco.entity_id,
    first_name: @second_portco_user.first_name,
    last_name: @second_portco_user.last_name,
    email: @second_portco_user.email,
    approved: true
  )
end

Given('the user {string} has the tag {string}') do |first_name, tag|
  user = User.find_by!(first_name: first_name)
  # Append the tag without clobbering existing tags
  existing = user.tag_list.to_s.split(',').map(&:strip).reject(&:blank?)
  user.update!(tag_list: (existing | [tag]).join(','))
end

Given('a KPI report shell exists for {string} as of {string}') do |portco_name, as_of|
  steps %(Given a KPI report shell exists for "#{portco_name}" as of "#{as_of}" with status "shell_created")
end

Given('a KPI report shell exists for {string} as of {string} with status {string}') do |portco_name, as_of, status|
  portco = Investor.find_by!(investor_name: portco_name)
  attrs = {
    entity: @entity,
    portfolio_company: portco,
    user: @user,
    as_of: Date.parse(as_of),
    period: 'Quarter',
    tag_list: 'Actual',
    enable_portco_upload: true,
    status: status
  }
  attrs[:submitted_at] = Time.current if %w[submitted reviewed].include?(status)
  @kpi_report = KpiReport.create!(attrs)
end

# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────

Given('I am logged in as the fund admin') do
  visit('/users/sign_in')
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: 'password')
  click_on('Log In')
  sleep(1)
end

Given('I am logged in as the portco user') do
  visit('/users/sign_in')
  fill_in('user_email', with: @portco_user.email)
  fill_in('user_password', with: 'password')
  click_on('Log In')
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# NAVIGATION & ACTIONS
# ─────────────────────────────────────────────────────────────────────────────

When('I create a KPI report shell for {string} as of {string} with period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(new_kpi_report_path(kpi_report: { portfolio_company_id: portco.id }))
  fill_in('kpi_report_as_of', with: as_of)
  select period, from: 'kpi_report_period'
  click_on('Save')
  sleep(1)
  @kpi_report = KpiReport.order(created_at: :desc).first
end

When('I open the KPI report for {string} as of {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report ||= KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
  visit(edit_kpi_report_path(@kpi_report))
end

When('I visit the portco pending dashboard') do
  visit(portco_pending_kpi_reports_path)
end

# For the magic link scenario: switch to a fresh Capybara session so there are
# no existing cookies — simulating a user who is not logged in.
When('I open the KPI report edit page as the portco user via a valid signed link') do
  signed_id = KpiReport.signed_id_for_user(@kpi_report, @portco_user)
  Capybara.session_name = :magic_link
  visit(edit_kpi_report_path(id: :shared, signed_id: signed_id))
end

When('I visit the KPI report edit page with an expired signed link') do
  verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
  expired_token = verifier.generate(
    { record_id: @kpi_report.id, email: @portco_user.email, model: 'KpiReport' },
    expires_in: -1.second,
    purpose: :shared_access
  )
  visit(edit_kpi_report_path(id: :shared, signed_id: expired_token))
end

# ─────────────────────────────────────────────────────────────────────────────
# NOTIFICATION TRIGGERS
# Notifications are triggered directly (bypassing UI) so tests don't depend on
# the notification modal layout, but we do verify the DB and email outcomes.
# ─────────────────────────────────────────────────────────────────────────────

When('I send a portco notification for {string} with date {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  SendPortcoNotificationJob.perform_now(
    [portco.id],
    user_id: @user.id,
    as_of: as_of,
    period: 'Quarter'
  )
  @kpi_report = KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
end

# Tests the controller validation by hitting it via the browser form.
When('I attempt to send a portco notification for {string} with invalid date {string}') do |portco_name, bad_date|
  portco = Investor.find_by!(investor_name: portco_name)
  # CSRF protection is disabled in test mode, so we submit without a token.
  visit(kpi_reports_path)
  page.execute_script(<<~JS)
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = '#{send_portco_notification_kpi_reports_path}';
    [
      ['portfolio_company_ids[]', '#{portco.id}'],
      ['as_of', '#{bad_date}'],
      ['period', 'Quarter']
    ].forEach(([n, v]) => {
      const i = document.createElement('input');
      i.name = n; i.value = v; i.type = 'hidden';
      form.appendChild(i);
    });
    document.body.appendChild(form);
    form.submit();
  JS
  sleep(1)
end

When('I send a portco notification to all portfolio companies with date {string}') do |as_of|
  ids = Investor.where(entity_id: @entity.id, category: 'Portfolio Company').pluck(:id)
  SendPortcoNotificationJob.perform_now(ids, user_id: @user.id, as_of: as_of, period: 'Quarter')
end

When('the portco notification service runs for the report') do
  SendPortcoNotification.call(model: @kpi_report, entity_id: @entity.id)
end

When('the periodic KPI reminder job runs') do
  @portfolio_company ||= @kpi_report.portfolio_company
  GeneratePeriodicKpiReportsJob.perform_now(@portfolio_company.id, @kpi_report.id)
end

# ─────────────────────────────────────────────────────────────────────────────
# FORM INTERACTIONS
# ─────────────────────────────────────────────────────────────────────────────

When('I click {string} and confirm the dialog') do |button_text|
  accept_confirm do
    click_on(button_text)
  end
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# STATUS ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('I should see the status badge {string}') do |status_text|
  expect(page).to have_css('.badge', text: status_text)
end

Then('the status badge shows {string}') do |status_text|
  expect(page).to have_css('.badge', text: status_text)
end

Then('the KPI report for {string} should have status {string}') do |portco_name, expected_status|
  portco = Investor.find_by!(investor_name: portco_name)
  report = @kpi_report || KpiReport.find_by!(portfolio_company: portco)
  report.reload
  expect(report.status).to eq(expected_status)
end

Then('the submitted_at timestamp is set on the report') do
  @kpi_report.reload
  expect(@kpi_report.submitted_at).to be_present
end

# ─────────────────────────────────────────────────────────────────────────────
# PAGE CONTENT ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('I should see {string} within the pending reports table') do |text|
  within('table') do
    expect(page).to have_content(text)
  end
end

Then('I should see a {string} link') do |link_text|
  expect(page).to have_link(link_text)
end

Then('I should see a {string} button') do |button_text|
  expect(page).to have_button(button_text)
end

Then('I should not see a {string} button') do |button_text|
  expect(page).not_to have_button(button_text)
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('the portco user receives a reminder email') do
  open_email(@portco_user.email)
  expect(current_email).to be_present
  expect(current_email.subject).to include('Reminder to report KPIs')
end

Then('the reminder email body contains the link expiry date') do
  open_email(@portco_user.email)
  expect(current_email.body).to include('valid until')
end

Then('the reminder email body contains {string}') do |text|
  open_email(@portco_user.email)
  expect(current_email.body).to include(text)
end

Then('the portco user receives no email') do
  open_email(@portco_user.email)
  expect(current_email).to be_nil
end

Then('the portco user for {string} receives a reminder email') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  user = portco.reload.notification_users.first
  open_email(user.email)
  expect(current_email).to be_present
  expect(current_email.subject).to include('Reminder to report KPIs')
end

Then('the portco user for {string} receives no email') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  user = portco.approved_users.first
  open_email(user.email)
  expect(current_email).to be_nil
end

Then('the fund admin receives no submission email') do
  submission_emails = ActionMailer::Base.deliveries.select do |mail|
    mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
  end
  expect(submission_emails).to be_empty
end

Then('the fund admin receives a submission notification email') do
  eventually do
    submission_email = ActionMailer::Base.deliveries.find do |mail|
      mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
    end
    expect(submission_email).to be_present
  end
end

Then('the submission email subject contains {string}') do |text|
  submission_email = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
  end
  expect(submission_email.subject).to include(text)
end

Then('the portco user {string} receives a reminder email') do |first_name|
  user = User.find_by!(first_name: first_name)
  open_email(user.email)
  expect(current_email).to be_present
  expect(current_email.subject).to include('Reminder to report KPIs')
end

Then('the user {string} receives no email') do |first_name|
  user = User.find_by!(first_name: first_name)
  open_email(user.email)
  expect(current_email).to be_nil
end

# ─────────────────────────────────────────────────────────────────────────────
# SESSION TEARDOWN
# ─────────────────────────────────────────────────────────────────────────────

# Reset the magic-link Capybara session after the unauthenticated scenario
# so it does not bleed into any subsequent scenario.
After('@kpi_magic_link') do
  Capybara.session_name = :default
  Capybara.reset_sessions!
end
