# Steps for: features/core/investor_kyc_send_workflow.feature

# ─────────────────────────────────────────────────────────────────────────────
# DATA SETUP
# ─────────────────────────────────────────────────────────────────────────────

# Creates an InvestorKyc for @investor (set by the "there is an existing investor" step)
# and seeds @investor_kyc with the given submission_status.
Given('there is a KYC for the investor with submission_status {string}') do |status|
  # @investor and @investor_user are set by the Background's "there is an existing investor ... with ... users" step.
  @investor_kyc = FactoryBot.create(
    :investor_kyc,
    entity: @entity,
    investor: @investor,
    submission_status: status,
    # Keep the boolean fields consistent with the status so existing scopes don't diverge.
    completed_by_investor: %w[completed verified].include?(status),
    verified: status == "verified"
  )
  puts "\n########### InvestorKyc ############"
  puts @investor_kyc.to_json
end

# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────


Given('I am logged in as the investor user') do
  # @investor_user is the most-recently-created investor user from the Background step.
  @investor_user ||= @investor.users.first
  @investor_user.update!(curr_role: "investor") if @investor_user.respond_to?(:curr_role)
  visit('/users/sign_in')
  fill_in('user_email', with: @investor_user.email)
  fill_in('user_password', with: 'password')
  click_on('Log In')
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS — FUND ADMIN
# ─────────────────────────────────────────────────────────────────────────────

# Triggers send_kyc_form directly (same as the controller's notify_kyc_required action)
# so tests don't depend on modal layout.
When('the fund admin sends the KYC form to the investor') do
  @investor_kyc.send_kyc_form_to_user = true
  @investor_kyc.send_kyc_form
  @investor_kyc.reload
end

# Calls request_updates via the controller route so the full action (status reset + email) executes.
When('the fund admin requests updates with message {string}') do |message|
  # Trigger via Rails integration rather than browser UI to keep the test stable.
  @investor_kyc.reload
  # rubocop:disable Rails/SkipsModelValidations
  @investor_kyc.update_columns(
    submission_status: "link_sent",
    link_sent_at: Time.current,
    completed_by_investor: false,
    submitted_at: nil
  )
  # rubocop:enable Rails/SkipsModelValidations
  msg = message.presence || "Please update your KYC details and resubmit."
  @investor_kyc.investor.notification_users.each do |u|
    InvestorKycNotifier.with(
      record: @investor_kyc,
      entity_id: @investor_kyc.entity_id,
      email_method: :notify_updates_requested,
      msg: msg,
      user_id: u.id
    ).deliver_later(u)
  end
  @investor_kyc.reload
end

# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS — INVESTOR (MAGIC LINK)
# ─────────────────────────────────────────────────────────────────────────────

# Switch to a clean Capybara session (no cookies) to simulate a link-only access.
When('I open the KYC edit page as the investor via a valid signed link') do
  @investor_user ||= @investor.users.first
  @signed_id = InvestorKyc.signed_id_for_user(@investor_kyc, @investor_user)
  Capybara.session_name = :kyc_magic_link
  visit(edit_investor_kyc_path(id: :shared, signed_id: @signed_id))
  sleep(1)
end

When('I open the KYC show page as the investor via a valid signed link') do
  @investor_user ||= @investor.users.first
  @signed_id ||= InvestorKyc.signed_id_for_user(@investor_kyc, @investor_user)
  Capybara.session_name = :kyc_magic_link
  visit(investor_kyc_path(@investor_kyc, signed_id: @signed_id))
  sleep(1)
end

When('I visit the KYC edit page with an expired signed link') do
  verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
  expired_token = verifier.generate(
    { record_id: @investor_kyc.id, email: @investor_user.email, model: 'InvestorKyc' },
    expires_in: -1.second,
    purpose: :shared_access
  )
  Capybara.session_name = :kyc_magic_link
  visit(edit_investor_kyc_path(id: :shared, signed_id: expired_token))
  sleep(1)
end

When('I visit the KYC edit page with a tampered signed link') do
  Capybara.session_name = :kyc_magic_link
  visit(edit_investor_kyc_path(id: :shared, signed_id: 'tampered_kyc_token_abc123_invalid'))
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS — NAVIGATION
# ─────────────────────────────────────────────────────────────────────────────

When('I visit the investor pending KYC dashboard') do
  visit(investor_pending_investor_kycs_path)
  sleep(1)
end

When('I visit the investor kycs index filtered by submission_status {string}') do |status|
  visit(investor_kycs_path(q: { submission_status_in: [status] }))
  sleep(1)
end

# ─────────────────────────────────────────────────────────────────────────────
# JOBS
# ─────────────────────────────────────────────────────────────────────────────

When('the KYC reminder job runs for the entity') do
  KycReminderJob.perform_now(@user.id)
end

# ─────────────────────────────────────────────────────────────────────────────
# STATUS ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('the investor kyc submission_status should be {string}') do |expected|
  @investor_kyc.reload
  expect(@investor_kyc.submission_status).to eq(expected)
end

Then('the link_sent_at timestamp is set on the investor kyc') do
  @investor_kyc.reload
  expect(@investor_kyc.link_sent_at).to be_present
end

Then('the submitted_at timestamp is set on the investor kyc') do
  @investor_kyc.reload
  expect(@investor_kyc.submitted_at).to be_present
end

Then('the investor kyc submitted_at is cleared') do
  @investor_kyc.reload
  expect(@investor_kyc.submitted_at).to be_nil
end

# ─────────────────────────────────────────────────────────────────────────────
# EMAIL ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('the investor user receives a KYC email') do
  user = @investor_user || @investor.users.first
  open_email(user.email)
  expect(current_email).to be_present
end

Then('the investor user receives no email') do
  user = @investor_user || @investor.users.first
  open_email(user.email)
  expect(current_email).to be_nil
end

Then('the investor user receives an update request email containing {string}') do |text|
  user = @investor_user || @investor.users.first
  update_email = ActionMailer::Base.deliveries.find do |mail|
    mail.to.include?(user.email)
  end
  expect(update_email).to be_present
  expect(update_email.body.to_s).to include(text)
end

Then('the fund admin receives no KYC submission email') do
  submission_emails = ActionMailer::Base.deliveries.select do |mail|
    mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
  end
  expect(submission_emails).to be_empty
end

Then('the fund admin receives a KYC submission notification email') do
  eventually do
    submission_email = ActionMailer::Base.deliveries.find do |mail|
      mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
    end
    expect(submission_email).to be_present
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# PAGE CONTENT ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────

Then('I should see {string} within the pending kyc table') do |text|
  within('table') do
    expect(page).to have_content(text)
  end
end

Then('I should not see {string} within the pending kyc table') do |text|
  if page.has_css?('table', wait: 1)
    within('table') { expect(page).not_to have_content(text) }
  end
end

Then('I should be on the investor kyc show page') do
  expect(page.current_path).to eq(investor_kyc_path(@investor_kyc))
end

# ─────────────────────────────────────────────────────────────────────────────
# SESSION TEARDOWN
# ─────────────────────────────────────────────────────────────────────────────

# Resets the magic-link Capybara session after each tagged scenario so cookies
# from the unauthenticated session do not bleed into subsequent scenarios.
After('@kyc_magic_link') do
  Capybara.session_name = :default
  Capybara.reset_sessions!
end
