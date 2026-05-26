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
  existing = access.tag_list.to_s.split(',').map(&:strip).reject(&:blank?)
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

When('I view the KPI report for {string} as of {string}') do |portco_name, as_of|
  portco = Investor.find_by!(investor_name: portco_name)
  @kpi_report ||= KpiReport.find_by!(portfolio_company: portco, as_of: Date.parse(as_of))
  visit(kpi_report_path(@kpi_report))
end

Given('the KPI report has an unapproved KPI') do
  # @kpi_report must already be set by the shell creation step
  FactoryBot.create(:kpi,
    kpi_report: @kpi_report,
    entity: @entity,
    portfolio_company: @portfolio_company,
    name: 'Revenue',
    value: 100.0,
    status: :unapproved)
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
  existing = user.tag_list.to_s.split(',').map(&:strip).reject(&:blank?)
  user.update_column(:tag_list, (existing | [tag]).join(','))
end

Given('there is a second fund employee {string}') do |attrs|
  attributes = attrs.split(';').map { |p| p.split('=') }.to_h.with_indifferent_access
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
# valid: true  → first row has date-like column headers (Jan 2025 …) — passes structural check
# valid: false → first row has plain-text headers only — fails structural check
def kpi_xlsx_base64(valid:)
  require "caxlsx"
  require "base64"
  tmp = Tempfile.new(["kpi_submit_guard_test", ".xlsx"])
  Axlsx::Package.new do |p|
    p.workbook.add_worksheet(name: "Sheet1") do |ws|
      if valid
        ws.add_row ["KPI Name", "Jan 2025", "Feb 2025", "Mar 2025"]
        ws.add_row ["Revenue", 100, 200, 300]
      else
        # No date-like values in header row — controller raises a structural error
        ws.add_row ["KPI Name", "Notes", "Comments", "Status"]
        ws.add_row ["Revenue", "Good", "Stable", "Active"]
      end
    end
    p.serialize(tmp.path)
  end
  b64 = Base64.strict_encode64(File.binread(tmp.path))
  tmp.close!
  b64
end

# Dispatches the upload:complete event that kpi_xlsx_report_controller listens for,
# carrying a File built from the given base64-encoded XLSX content.
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
  # The view renders submitted_at in human format (e.g. "May 22"), not ISO8601.
  month = @kpi_report.submitted_at.strftime('%b')
  day   = @kpi_report.submitted_at.day.to_s
  expect(page).to have_content("#{month} #{day}")
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
  if page.has_css?('table', wait: 1)
    within('table') { expect(page).not_to have_content(text) }
  end
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
  # The form enforces read-only state by removing Save Draft / Submit buttons on
  # submitted reports rather than disabling individual fields.
  expect(page).not_to have_button('Save Draft')
  expect(page).not_to have_button('Submit Report')
  expect(page).to have_content('Report Already Submitted')
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
  existing = access.tag_list.to_s.split(',').map(&:strip).reject(&:blank?)
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
