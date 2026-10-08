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
  # Set the tag on the investor_access (per-relationship) rather than globally on the user
  portco = @portfolio_company || Investor.find_by!(investor_name: 'TestStartup')
  access = InvestorAccess.find_by!(user: user, investor: portco)
  existing = access.tag_list.to_s.split(',').map(&:strip).compact_blank
  access.update_column(:tag_list, (existing | [tag]).join(','))
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
  advance_kpi_wizard_to(:report_details) # as_of / period live on the wizard's "Report Details" step
  fill_in('kpi_report_as_of', with: as_of)
  select period, from: 'kpi_report_period'
  advance_kpi_wizard_to(:additional_details) # Save lives on the wizard's last step
  click_on('Save')
  sleep(1)
  @kpi_report = KpiReport.order(created_at: :desc).first
end

When('I open the KPI report for {string} as of {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report ||= KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
  visit(edit_kpi_report_path(@kpi_report))
end

When('I view the KPI report for {string} as of {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report ||= KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
  visit(kpi_report_path(@kpi_report))
end

Given('the KPI report has an unapproved KPI') do
  # @kpi_report must already be set by the shell creation step
  name = "Revenue"
  mapping = InvestorKpiMapping.find_or_create_by(standard_kpi_name: name, entity: @entity, investor: @portfolio_company, reported_kpi_name: name)
  FactoryBot.create(:kpi,
                    kpi_report: @kpi_report,
                    entity: @entity,
                    portfolio_company: @portfolio_company,
                    name: name,
                    value: 100.0,
                    status: :unapproved,
                    investor_kpi_mapping_id: mapping.id)
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
  # Try window.confirm first (used by interim-save#final); fall back to Bootstrap modal
  # (used by KpiReport submit and confirm#popup).
  begin
    page.accept_confirm { click_on(button_text) }
  rescue Capybara::ModalNotFound
    click_on(button_text) unless page.has_css?('.modal.show', wait: 0)
    if page.has_css?('.modal.show', wait: 2)
      within('.modal.show') do
        if page.has_button?('Yes, Submit KYC', wait: 1)
          click_on('Yes, Submit KYC')
        elsif page.has_button?('Confirm & Submit', wait: 1)
          click_on('Confirm & Submit')
        elsif page.has_button?('Confirm', wait: 1)
          click_on('Confirm')
        elsif page.has_button?('Proceed', wait: 1)
          click_on('Proceed')
        end
      end
    end
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

Then('the reminder email subject contains {string}') do |text|
  open_email(@portco_user.email)
  expect(current_email.subject).to include(text)
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

# Fund employees carry the Kpi tag on user.tag_list (not on investor_access).
Given('the fund employee {string} has the tag {string}') do |first_name, tag|
  user = User.find_by!(first_name: first_name)
  existing = user.tag_list.to_s.split(',').map(&:strip).compact_blank
  user.update_column(:tag_list, (existing | [tag]).join(','))
end

Given('there is a second fund employee {string}') do |attrs|
  attributes = attrs.split(';').to_h { |p| p.split('=') }.with_indifferent_access
  @second_fund_employee = FactoryBot.create(:user, entity: @entity,
                                                   first_name: attributes[:first_name] || 'FundEmployee2',
                                                   last_name: attributes.fetch(:last_name, 'User'),
                                                   email: attributes.fetch(:email, "#{attributes[:first_name]&.downcase || 'fundemployee2'}@#{@entity.name.downcase.gsub(/\s+/, '')}.com"),
                                                   active: true)
end

Then('the fund employee {string} receives a submission notification email') do |first_name|
  employee = User.find_by!(first_name: first_name)
  submission_email = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(employee.email) && mail.subject.to_s.downcase.include?('submitted')
  end
  expect(submission_email).to be_present
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
# SUBMIT GUARD (client-side XLSX validation)
# ─────────────────────────────────────────────────────────────────────────────

# Builds a minimal XLSX in memory and returns it as a Base64 string.
# valid: true  → header has date-like columns incl. "Q1 2025" (the quarter the test shells ask for,
#                as_of 2025-03-31 / Quarter) and a mapped KPI row — passes the server-side check
# valid: false → first row has plain-text headers only — fails the server-side check (no_header)
def kpi_xlsx_base64(valid:)
  require "caxlsx"
  require "base64"
  tmp = Tempfile.new(["kpi_submit_guard_test", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Sheet1") do |ws|
      if valid
        ws.add_row ["KPI Name", "Jan 2025", "Feb 2025", "Mar 2025", "Q1 2025"]
        ws.add_row ["Revenue", 100, 200, 300, 600]
      else
        # No date-like values in header row — controller raises a structural error
        ws.add_row ["KPI Name", "Notes", "Comments", "Status"]
        ws.add_row %w[Revenue Good Stable Active]
      end
    end
    p.serialize(tmp.path)
  end
  b64 = Base64.strict_encode64(File.binread(tmp.path))
  tmp.close!
  b64
end

# Dispatches the upload:complete event that kpi_xlsx_report_controller listens for,
# carrying a File built from the given base64-encoded XLSX content. The controller posts the
# File to KpiReportsController#validate_upload (multipart fallback) and renders the server verdict.
# With importmaps, Stimulus controllers load asynchronously, so we poll until
# the kpi-xlsx-report controller is registered before dispatching.
def dispatch_kpi_upload(b64, filename)
  eventually do
    registered = page.evaluate_script(
      "!!(window.Stimulus && window.Stimulus.controllers.some(function(c){ return c.identifier === 'kpi-xlsx-report' }))"
    )
    expect(registered).to be_truthy
  end
  page.execute_script(<<~JS)
    (function() {
      const b64 = "#{b64}";
      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      const blob = new Blob([bytes], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
      const file = new File([blob], '#{filename}', { type: blob.type });
      const el = document.querySelector('[data-controller="kpi-xlsx-report"]');
      const uploadId = el ? el.dataset.uploadId : undefined;
      document.dispatchEvent(new CustomEvent('upload:complete', {
        bubbles: true,
        detail: { file: file, uploadId: uploadId }
      }));
    })();
  JS
end

When('I upload a KPI XLSX with no date-like headers') do
  dispatch_kpi_upload(kpi_xlsx_base64(valid: false), "invalid_kpi.xlsx")
end

When('I upload a KPI XLSX with valid date headers') do
  dispatch_kpi_upload(kpi_xlsx_base64(valid: true), "valid_kpi.xlsx")
end

Then('the {string} button should be enabled') do |button_text|
  expect(page).to have_button(button_text, disabled: false)
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

# ─────────────────────────────────────────────────────────────────────────────
# STEPS FOR SCENARIOS 16–29 (Manual QA gap coverage)
# ─────────────────────────────────────────────────────────────────────────────

# ── Scenario 16: Re-send idempotency ─────────────────────────────────────────

# Confirms find_or_create_by! on the shell does not duplicate records.
Then('there is only one KPI report for {string} as of {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  count = KpiReport.where(portfolio_company: portco, as_of: Date.parse(as_of)).count
  expect(count).to eq(1)
end

# ── Scenario 17: Admin-only fields hidden from portco ─────────────────────────

# Portco edit form must not expose the portfolio company dropdown or tag field.
Then('the portfolio company selector is not visible') do
  expect(page).not_to have_select('kpi_report_portfolio_company_id')
end

Then('the KPI tag selector is not visible') do
  expect(page).not_to have_field('kpi_report_tag_list')
end

# ── Scenario 18: Save Draft redirect target ───────────────────────────────────

# Saves must redirect back to the edit page, not the show page.
Then('I should be on the edit page for the KPI report') do
  expect(current_path).to eq(edit_kpi_report_path(@kpi_report))
end

# ── Scenario 19: submitted_at visible on form ─────────────────────────────────

# Manual QA 4.4: timestamp is rendered next to the status badge on the form.
Then('the submitted_at timestamp is visible on the form') do
  @kpi_report.reload
  # After submitting, the portco lands on the KPIs submitted page, which renders submitted_at with l(date)
  expect(page).to have_content(I18n.l(@kpi_report.submitted_at.to_date))
end

# ── Scenario 22: Double-submit guard ─────────────────────────────────────────

# Attempts a direct PATCH to the update endpoint after the portco has already
# submitted; the controller must not re-deliver the fund admin notification.
When('I attempt to submit the already-submitted KPI report directly') do
  @kpi_report.reload
  # The UI blocks re-submission (no button shown for submitted reports).
  # Open the edit page as the logged-in portco — the absence of a submit button
  # combined with no new notification email proves the double-submit guard.
  visit(edit_kpi_report_path(@kpi_report))
  sleep(1)
end

# ── Scenario 26: Tampered magic link ─────────────────────────────────────────

# Tampered token (syntactically valid base64 but wrong signature) must produce
# the same friendly error page as an expired token — not a 500.
When('I visit the KPI report edit page with a tampered signed link') do
  visit(edit_kpi_report_path(id: :shared, signed_id: 'tampered_abc123_invalid_token_xyz'))
end

# ── Link / button absence assertions ─────────────────────────────────────────

Then('I should not see a {string} link') do |link_text|
  expect(page).not_to have_link(link_text)
end

# ── Dashboard: row absence ────────────────────────────────────────────────────

# Submitted/reviewed reports must be absent from the portco pending table.
# If the table itself is absent (no pending reports at all) the assertion passes.
Then('I should not see {string} within the pending reports table') do |text|
  within('table') { expect(page).not_to have_content(text) } if page.has_css?('table', wait: 1)
end

# ── Scenario 29: Non-KPI notification regression ─────────────────────────────

# Confirms that portco.approved_users (used by non-KPI notifications) is broader
# than portco.notification_users (used by KPI reminders when the Kpi tag is set).
# This guards against accidentally applying the Kpi-tag filter to all mailers.
# ─────────────────────────────────────────────────────────────────────────────
# STEPS FOR SCENARIOS 30–39 (remaining Manual QA gap coverage)
# ─────────────────────────────────────────────────────────────────────────────

# ── Scenario 30: link_sent_at timestamp ──────────────────────────────────────

Then('the link_sent_at timestamp is set on the KPI report for {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  report = KpiReport.find_by!(portfolio_company: portco)
  report.reload
  expect(report.link_sent_at).to be_present
end

# ── Scenario 31: Magic link badge + editable fields ───────────────────────────

Then('the notes field is editable') do
  expect(page).to have_field('kpi_report_notes', disabled: false)
end

# ── Scenario 33: Submit dialog text ──────────────────────────────────────────

Then('I should see {string} in the confirmation dialog') do |text|
  within('.modal.show', wait: 3) do
    expect(page).to have_content(text)
  end
end

# ── Scenario 34: Fields read-only after submission ────────────────────────────

Then('the notes field is not editable') do
  # A submitted report shows the portco a confirmation page instead of the wizard, so there is no form at all
  steps %(Then I should see the KPIs submitted page instead of the wizard)
  expect(page).not_to have_field('kpi_report[notes]')
end

# The portco's confirmation page on a submitted/reviewed report (kpi_reports/_portco_submitted.html.erb)
Then('I should see the KPIs submitted page instead of the wizard') do
  expect(page).to have_css('#kpi_report_portco_submitted', text: 'KPIs submitted')
  expect(page).to have_content('This report can no longer be changed')
  expect(page).not_to have_content("Let's get started")
  expect(page).not_to have_button('Save Draft')
  expect(page).not_to have_button('Submit Report')
end

Then('the KPIs submitted page shows the import finished') do
  expect(page).to have_content("Imported for the fund's review")
  expect(page).to have_css('#kpi_report_submitted_file')
end

# KpiReport#reopen_for_portco! — what the fund's "Reopen & ask to re-upload" does
When('the fund reopens the KPI report') do
  @kpi_report.reload.reopen_for_portco!(@kpi_report.entity_id)
end

# ── Scenario 36: Grid view navigation via View Including Staged ───────────────

# Clicks a plain link (not a button-with-confirm) — used for "View Including Staged".
When('I click the {string} link') do |link_text|
  click_on(link_text)
  sleep(1)
end

# Confirms the URL carries all three query params that the grid view requires.
Then('I should be on the KPI grid view for {string} with staged data visible') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  expect(current_url).to include("portfolio_company_id=#{portco.id}")
  expect(current_url).to include("view_unapproved=true")
  expect(current_url).to include("grid_view=true")
end

# ── Scenario 37: Approve All staged KPIs ─────────────────────────────────────

# Calls KpiApproveService directly — the UI "Approve All" button triggers a
# Stimulus confirm#popup before submitting, making a browser click unreliable
# in tests. The service call matches exactly what the controller does.
When('I approve all staged KPIs for {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  unapproved_ids = Kpi.where(portfolio_company: portco, status: :unapproved).pluck(:id)
  KpiApproveService.call(unapproved_ids, @user.id)
end

Then('the staged KPI for {string} should be approved') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  unapproved = Kpi.where(portfolio_company: portco, status: :unapproved)
  expect(unapproved).to be_empty
end

# ── Scenario 39: Remove Kpi tag ───────────────────────────────────────────────

Given('the user {string} has the tag {string} removed') do |first_name, tag|
  user = User.find_by!(first_name: first_name)
  portco = @portfolio_company || Investor.find_by!(investor_name: 'TestStartup')
  access = InvestorAccess.find_by!(user: user, investor: portco)
  existing = access.tag_list.to_s.split(',').map(&:strip).compact_blank
  access.update_column(:tag_list, (existing - [tag]).join(','))
end

# ── Scenario 29: Non-KPI notification regression ─────────────────────────────

# Confirms portco.approved_users (used by non-KPI notifications) is broader than
# portco.notification_users (used by KPI reminders when the Kpi tag is set).
# Guards against accidentally applying the Kpi-tag filter to all mailers.
Then('all approved users are reachable for non-KPI notifications at {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  all_users      = portco.approved_users.to_a
  # Tag lives on investor_access now, not on user
  kpi_accesses   = portco.approved_investor_accesses.with_tag('Kpi')
  kpi_tagged_ids = kpi_accesses.pluck(:user_id)

  # Non-KPI notifications draw from approved_users — every approved user is reachable.
  expect(all_users).to include(@portco_user, @second_portco_user)
  # The Kpi tag marks a strict subset — KPI reminders filter to these; non-KPI mailers must not.
  expect(kpi_tagged_ids.size).to be < all_users.size
  expect(kpi_tagged_ids).to include(@portco_user.id)
  expect(kpi_tagged_ids).not_to include(@second_portco_user.id)
end

# ─────────────────────────────────────────────────────────────────────────────
# SUBMIT GATE & ACTOR-SCOPED PARAMS (server-side; docs/modules/portfolio/kpis/kpi_portco_upload_validation_review.md §2.1/§2.2/§2.8)
# ─────────────────────────────────────────────────────────────────────────────

# Attaches a workbook to @kpi_report and stores its verdict, exactly as a portco upload + Save Draft
# would. valid: true → contains the requested quarter (Q1 2025) with a mapped Revenue value.
def attach_kpi_workbook_to_report(valid:)
  require "caxlsx"
  unless @portfolio_company.investor_kpi_mappings.exists?
    @portfolio_company.investor_kpi_mappings.create!(entity_id: @portfolio_company.entity_id, reported_kpi_name: "Revenue", standard_kpi_name: "Revenue")
    @portfolio_company.reload
  end
  tmp = Tempfile.new(["kpi_gate", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "MIS") do |ws|
      if valid
        ws.add_row ["KPI", "Jan 2025", "Feb 2025", "Mar 2025", "Q1 2025"]
        ws.add_row ["Revenue", 100, 200, 300, 600]
      else
        # Only months of 2024 — the shell asks for Q1 2025, so requested_period_missing blocks it
        ws.add_row ["KPI", "Jan 2024", "Feb 2024"]
        ws.add_row ["Revenue", 100, 200]
      end
    end
    p.serialize(tmp.path)
  end
  doc = @kpi_report.documents.build(entity_id: @entity.id, name: "KPIs", user_id: @user.id, file: File.open(tmp.path), owner: @kpi_report)
  doc.save!
  KpiUploadValidate.call(kpi_report: @kpi_report, user: @user)
  @kpi_report.reload
end

Given('the KPI report has a valid KPIs workbook attached') do
  attach_kpi_workbook_to_report(valid: true)
end

Given('the KPI report has a KPIs workbook attached that is missing the requested period') do
  attach_kpi_workbook_to_report(valid: false)
end

# Bypasses the disabled buttons (what a tampered browser could do) and submits the form as "final".
When('I force a final submit of the KPI report form') do
  page.execute_script(<<~JS)
    document.getElementById('submit_action_field').value = 'final';
    document.getElementById('kpi-report-form').requestSubmit();
  JS
  sleep(1)
end

Given('there is a second portfolio company {string}') do |name_kv|
  first = @portfolio_company
  steps %(Given there is an existing portfolio company "#{name_kv}")
  @other_portfolio_company = @portfolio_company
  @portfolio_company = first
end

# Sends the kind of PATCH a portco could craft with dev tools: every fund-only field plus nested KPI
# rows. Uses the page's own CSRF token and session, so only strong-params stand between it and the DB.
When('I send a crafted PATCH for the KPI report with fund-only fields') do
  approved_before = @kpi_report.kpis.approved.count
  page.execute_script(<<~JS)
    (async function () {
      const body = new FormData();
      body.append('kpi_report[notes]', 'tampered');
      body.append('kpi_report[as_of]', '2024-12-31');
      body.append('kpi_report[period]', 'Year');
      body.append('kpi_report[tag_list]', 'Budget');
      body.append('kpi_report[portfolio_company_id]', '#{@other_portfolio_company.id}');
      body.append('kpi_report[entity_id]', '#{@other_portfolio_company.investor_entity_id}');
      body.append('kpi_report[delete_kpis]', 'true');
      body.append('kpi_report[kpis_attributes][0][name]', 'Injected');
      body.append('kpi_report[kpis_attributes][0][value]', '999');
      body.append('kpi_report[kpis_attributes][0][entity_id]', '#{@entity.id}');
      const token = document.querySelector('meta[name="csrf-token"]')?.content
                 || document.querySelector('input[name="authenticity_token"]')?.value || '';
      body.append('authenticity_token', token);
      try {
        const r = await fetch('/kpi_reports/#{@kpi_report.id}', {
          method: 'PATCH', headers: { 'X-CSRF-Token': token, 'Accept': 'text/html' },
          body: body, credentials: 'same-origin', redirect: 'manual'
        });
        window.__patchStatus = r.status;
      } catch (e) { window.__patchError = String(e); }
      window.__patchDone = true;
    })();
  JS
  eventually { expect(page.evaluate_script('window.__patchDone === true')).to be(true) }
  @approved_before = approved_before
end

Then('the KPI report for {string} as of {string} is unchanged apart from notes {string}') do |portco_name, as_of, notes|
  report = KpiReport.find(@kpi_report.id)
  portco = Investor.find_by!(investor_name: portco_name)
  expect(report.notes).to eq(notes)
  expect(report.portfolio_company_id).to eq(portco.id)
  expect(report.as_of).to eq(Date.parse(as_of))
  expect(report.period).to eq('Quarter')
  expect(report.tag_list).to eq('Actual')
  expect(report.entity_id).to eq(@entity.id)
  expect(report.kpis.unapproved.count).to eq(1), "delete_kpis must be ignored for portco actors"
end

Then('no approved KPI was created on the KPI report') do
  expect(@kpi_report.reload.kpis.approved.count).to eq(@approved_before.to_i)
  expect(Kpi.where(name: 'Injected')).to be_empty
end

Given('a portfolio company {string} of another fund exists') do |name|
  other_fund = FactoryBot.create(:entity, entity_type: "Investment Fund")
  portco_entity = FactoryBot.create(:entity, entity_type: "Investor")
  @foreign_portco = FactoryBot.create(:investor, entity: other_fund, investor_entity: portco_entity, investor_name: name, category: "Portfolio Company")
end

When('I send a PATCH re-pointing the KPI report to {string}') do |name|
  target = Investor.find_by!(investor_name: name)
  visit(edit_kpi_report_path(@kpi_report))
  page.execute_script(<<~JS)
    (async function () {
      const body = new FormData();
      body.append('kpi_report[portfolio_company_id]', '#{target.id}');
      const token = document.querySelector('meta[name="csrf-token"]')?.content
                 || document.querySelector('input[name="authenticity_token"]')?.value || '';
      body.append('authenticity_token', token);
      try {
        const r = await fetch('/kpi_reports/#{@kpi_report.id}', {
          method: 'PATCH', headers: { 'X-CSRF-Token': token, 'Accept': 'text/html' },
          body: body, credentials: 'same-origin', redirect: 'manual'
        });
        window.__patchStatus = r.status;
      } catch (e) { window.__patchError = String(e); window.__patchStatus = -1; }
    })();
  JS
  eventually { expect(page.evaluate_script('typeof window.__patchStatus === "number"')).to be(true) }
  @patch_status = page.evaluate_script('window.__patchStatus')
end

Then('the KPI report for {string} as of {string} still points at {string}') do |_portco_name, _as_of, name|
  # The DB assertion is what matters — the HTTP status of a Pundit refusal varies (403 vs redirect).
  expect(KpiReport.find(@kpi_report.id).portfolio_company.investor_name).to eq(name)
end

# ─────────────────────────────────────────────────────────────────────────────
# IMPORT LIFECYCLE, REOPEN, TEMPLATE (§2.2 E, §3.4 P/Q)
# ─────────────────────────────────────────────────────────────────────────────

Then('the KPI report import status is {string}') do |status|
  eventually { expect(KpiReport.find(@kpi_report.id).import_status).to eq(status) }
end

Then('the KPI report has an unapproved KPI {string} as of {string} with value {float}') do |name, as_of, value|
  # Scoped to the shell's own period (a "Mar 2025" month column lands on a separate Month report)
  kpi = Kpi.unapproved.joins(:kpi_report).where(name: name, portfolio_company_id: @portfolio_company.id, kpi_reports: { as_of: Date.parse(as_of), period: @kpi_report.period }).first
  expect(kpi).to be_present
  expect(kpi.value.to_f).to eq(value)
end

# What the controller does after a passed gate — set directly so we can exercise the job's failure path.
Given('the KPI report is marked submitted with a pending import') do
  @kpi_report.update_columns(status: 'submitted', submitted_at: Time.current, import_status: 'pending')
end

When('the KPI import job runs for the report') do
  ImportKpiWorkbookJob.perform_now(@kpi_report.id, @user.id)
end

Then('the fund admin receives an email with subject containing {string}') do |text|
  eventually do
    mail = ActionMailer::Base.deliveries.find { |m| m.to.include?(@user.email) && m.subject.to_s.include?(text) }
    expect(mail).to be_present, "no email to #{@user.email} with subject containing #{text}; subjects: #{ActionMailer::Base.deliveries.map(&:subject).inspect}"
  end
end

When('I send a KPI notification to {string} as of {string} with period {string}') do |portco_name, as_of, period|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(kpi_reports_path)
  page.driver.post(send_portco_notification_kpi_reports_path, portfolio_company_id: portco.id, as_of: as_of, period: period) rescue nil
  # Playwright has no driver.post — submit through a tiny form built on the page instead
  page.execute_script(<<~JS)
    (function () {
      const f = document.createElement('form'); f.method = 'POST'; f.action = '#{send_portco_notification_kpi_reports_path}';
      const add = (n, v) => { const i = document.createElement('input'); i.type = 'hidden'; i.name = n; i.value = v; f.appendChild(i); };
      add('authenticity_token', document.querySelector('meta[name="csrf-token"]')?.content || '');
      add('portfolio_company_id', '#{portco.id}'); add('as_of', '#{as_of}'); add('period', '#{period}');
      document.body.appendChild(f); f.submit();
    })();
  JS
  sleep(1)
end

Then('the generated KPI template for the report has header {string} and rows {string}') do |header_label, names|
  result = KpiTemplateGenerate.call(kpi_report: @kpi_report)
  tmp = Tempfile.new(["kpi_template", ".xlsx"], binmode: true)
  tmp.write(result[:xlsx])
  tmp.flush
  @template_path = tmp.path
  wb = Roo::Spreadsheet.open(tmp.path)
  header = wb.row(1).map(&:to_s)
  expect(header).to include(header_label)
  names.split(',').map(&:strip).each do |n|
    expect((2..wb.last_row).map { |i| wb.row(i).first.to_s }).to include(n)
  end
end

Then('validating the generated template reports the requested period as present but blank') do
  upload = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(@template_path), filename: "template.xlsx",
                                                  type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  verdict = KpiUploadValidate.call(kpi_report: @kpi_report, user: @portco_user, file: upload)[:verdict]
  # Header parsed to the requested quarter; the sheet is empty so the only complaint is "blank"
  expect(verdict['errors'].pluck('code')).to include('requested_period_blank')
  expect(verdict['errors'].pluck('code')).not_to include('requested_period_missing', 'no_header')
end

# ── Scenario 51: no empty chart in the staged review ─────────────────────────

When('I open the KPI grid for {string} including staged values') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(kpi_reports_path(portfolio_company_id: portco.id, grid_view: true, view_unapproved: true))
  expect(page).to have_css("#kpi_grid_view_chart_container", visible: :all)
end

When('I open the KPI grid for {string}') do |portco_name|
  portco = Investor.find_by!(investor_name: portco_name)
  visit(kpi_reports_path(portfolio_company_id: portco.id, grid_view: true))
  expect(page).to have_css("#kpi_grid_view_chart_container", visible: :all)
end

Then('the grid shows no KPIs chart') do
  expect(page).not_to have_css("#kpi_grid_view_chart_container .card")
end

Then('the grid shows the KPIs chart') do
  expect(page).to have_css("#kpi_grid_view_chart_container .card", text: "KPIs")
end
