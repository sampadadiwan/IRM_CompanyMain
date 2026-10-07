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

# Same as above but blanks every standard mandatory field (everything the model's
# `presence: true` validation covers except kyc_type, which defaults at the DB level
# and is effectively always set by the wizard's Individual/Non Individual step).
# Saved with validate:false purely to get a persisted fixture in this state — the
# scenario itself proves the investor's full *submit* still gets blocked server-side.
Given('there is a KYC for the investor with submission_status {string} and no mandatory fields filled in') do |status|
  @investor_kyc = FactoryBot.build(
    :investor_kyc,
    entity: @entity,
    investor: @investor,
    submission_status: status,
    completed_by_investor: %w[completed verified].include?(status),
    verified: status == "verified",
    full_name: nil, PAN: nil, birth_date: nil, address: nil, corr_address: nil,
    bank_name: nil, bank_branch: nil, bank_account_type: nil, bank_account_number: nil, ifsc_code: nil
  )
  @investor_kyc.form_type = @form_type if @form_type.present?
  @investor_kyc.save!(validate: false)
  puts "\n########### InvestorKyc (no mandatory fields filled in) ############"
  puts @investor_kyc.to_json
end

# Links a capital commitment (on the current @fund, for the Background's @investor) to the
# current @investor_kyc, so InvestorKycPolicy#show?'s fund-scoped branches have something to match.
Given('the investor kyc has a capital commitment on the fund') do
  @capital_commitment = FactoryBot.create(
    :capital_commitment, fund: @fund, entity: @entity, investor: @investor, investor_kyc: @investor_kyc
  )
end

Given('the user {string} has extended permission {string}') do |email, permission|
  user = User.find_by!(email: email)
  user.extended_permissions.set(permission.to_sym)
  user.save!
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

# Fires InvestorKycAction#updated_notification (investor_user: true, validate: true) without
# the overhead of a full browser submit — this is the same Trailblazer step the controller's
# "Submit KYC" action runs (InvestorKycsController#update -> InvestorKycUpdate.call).
When('the investor submits an update to the KYC') do
  @investor_kyc.reload
  result = InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user: true, validate: true)
  expect(result).to be_success
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

Then('the investor kyc submission_status should not be {string}') do |unexpected|
  @investor_kyc.reload
  expect(@investor_kyc.submission_status).not_to eq(unexpected)
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

# Confirms the fix for the in-app notification body regression: InvestorKycNotifier#message is
# shared by the email and the in-app notification, so restoring msg: in the controller (without
# which @message/the notification's stored message resolves to nil) must leave the in-app
# notification with a real body, while the email itself ignores msg: entirely and always shows
# its own formatted default text (notify_kyc_submitted.html.erb no longer branches on @message).
Then('the fund admin has a KYC submitted notification with a non-blank message') do
  eventually do
    notification = Noticed::Notification.where(recipient: @user).order(:created_at).last
    expect(notification).to be_present
    expect(notification.message).to be_present
  end
end

Then('the fund admin\'s KYC submission email body reads the default submitted text') do
  eventually do
    submission_email = ActionMailer::Base.deliveries.find do |mail|
      mail.to.include?(@user.email) && mail.subject.to_s.downcase.include?('submitted')
    end
    expect(submission_email.body.to_s).to include('has submitted their KYC for review')
  end
end

# "updated" (InvestorKycMailer#notify_kyc_updated) is deliberately distinct from "submitted"
# (notify_kyc_submitted, asserted above) - they are two separate notification code paths.
Then('the user {string} receives a KYC updated notification email') do |email|
  eventually do
    mail = ActionMailer::Base.deliveries.find do |m|
      m.to.include?(email) && m.subject.to_s.downcase.include?('updated')
    end
    expect(mail).to be_present
  end
end

Then('the user {string} does not receive a KYC updated notification email') do |email|
  mail = ActionMailer::Base.deliveries.find do |m|
    m.to.include?(email) && m.subject.to_s.downcase.include?('updated')
  end
  expect(mail).to be_nil
end

# Stronger than "receives a KYC updated notification email" - asserts exactly one delivery, not
# just at least one. Used to prove notify_kyc's two loops are deduplicated by user id.
Then('the user {string} receives exactly one KYC updated notification email') do |email|
  eventually do
    mails = ActionMailer::Base.deliveries.select do |m|
      m.to.include?(email) && m.subject.to_s.downcase.include?('updated')
    end
    expect(mails.size).to eq(1)
  end
end

# Nulls out advisor_entity_id on an existing user - reproduces the legacy state InvestorAdvisor's
# own comments document (an advisor account created before ensure_advisor_home existed), which
# not_investor_advisor_roles (where(advisor_entity_id: nil)) can't distinguish from a plain
# non-advisor employee.
Given('the user {string} has a nil advisor_entity_id') do |email|
  # rubocop:disable Rails/SkipsModelValidations
  User.find_by!(email: email).update_column(:advisor_entity_id, nil)
  # rubocop:enable Rails/SkipsModelValidations
end

# Same as "the advisor {string} is switched into entity {string}", but with a caller-chosen
# allowed_roles list and every module permission EXCEPT enable_kycs - used to reproduce a
# switched-in advisor whose grant passes show?'s permissioned_employee?/company_admin bypass
# (unrelated to enable_kycs) while their own grant's enable_kycs flag is off.
Given('the advisor {string} is switched into entity {string} with allowed_roles {string} and enable_kycs disabled') do |email, entity_kv, roles_csv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  ia = InvestorAdvisor.new(user:, entity:, email: user.email, allowed_roles: roles_csv.split(',').map(&:strip))
  (User.permissions.keys - [:enable_kycs]).each { |permission| ia.permissions.set(permission) }
  ia.save!
  ia.switch(user)
  user.reload
end

# ─────────────────────────────────────────────────────────────────────────────
# Direct InvestorKycPolicy#show? assertions, and InvestorAdvisor grant fixtures with a
# custom allowed_roles - used by the review-fix scenarios (16-19) to exercise show?'s
# branch structure directly, rather than only indirectly via notify_kyc.
# ─────────────────────────────────────────────────────────────────────────────

Then('the user {string} should have show access to the investor kyc') do |email|
  user = User.find_by!(email: email)
  expect(InvestorKycPolicy.new(user, @investor_kyc).show?).to be_truthy
end

Then('the user {string} should not have show access to the investor kyc') do |email|
  user = User.find_by!(email: email)
  expect(InvestorKycPolicy.new(user, @investor_kyc).show?).to be_falsey
end

# Same as above, for the investor user set by "there is an existing investor ... with ... users"
# (a FactoryBot-random email, so it can't be named directly in Gherkin).
Then('the investor user should have show access to the investor kyc') do
  expect(InvestorKycPolicy.new(@investor_user, @investor_kyc).show?).to be_truthy
end

# Same shape as "there is an existing investor {string} with {string} users", but sets the
# investor entity's entity_type BEFORE the investor user is created - User#setup_defaults reads
# entity_type at user-creation time (before_create), so setting it afterward (e.g. via the shared
# "there is an existing investor entity" step, whose key_values also re-applies to @investor
# itself and has no entity_type attribute there) is too late to affect which role the user gets.
# Used to reproduce a corporate/fund-of-funds LP user, who gets :employee (not :investor) from
# setup_defaults for entity_type "Company" or a fund type.
Given('there is an existing investor {string} of entity_type {string} with {string} users') do |arg1, entity_type, count|
  @investor_entity = FactoryBot.build(:entity, entity_type:)
  key_values(@investor_entity, arg1)
  @investor_entity.save!
  EntityIndex.import

  @investor = FactoryBot.create(:investor, investor_entity_id: @investor_entity.id, entity_id: @entity.id, investor_name: @investor_entity.name)
  key_values(@investor, arg1)
  @investor.save!

  (1..count.to_i).each do
    @investor_user = FactoryBot.create(:user, entity: @investor_entity)
    @investor_access = InvestorAccess.create!(investor: @investor, user: @investor_user,
                                              entity_id: @investor.entity_id,
                                              first_name: @investor_user.first_name,
                                              last_name: @investor_user.last_name,
                                              email: @investor_user.email, approved: true)
  end
end

# Creates an InvestorAdvisor grant on the given entity for the given user, with a caller-chosen
# allowed_roles list, WITHOUT switching the user in (their own entity_id is untouched) - mirrors
# "there is an investor advisor record for {string} on entity {string}" but lets the allowed_roles
# vary, and grants full module permissions (so permissions.enable_kycs? reflects the fix under
# test, not an incidental missing module flag - same reasoning as "the advisor ... is switched
# into entity"). The grantee must already hold the investor_advisor role (InvestorAdvisor's own
# ensure_user validation requires it) - set that up with a prior "the user ... has role
# 'investor_advisor'" step.
Given('there is an investor advisor grant for {string} on entity {string} with allowed_roles {string}') do |email, entity_kv, roles_csv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  ia = InvestorAdvisor.new(user:, entity:, email: user.email, allowed_roles: roles_csv.split(',').map(&:strip))
  permission_keys = User.permissions.keys
  permission_keys.each { |permission| ia.permissions.set(permission) }
  ia.save!
end

# Same as above, but writes allowed_roles as a legacy symbol-serialized array ([:employee])
# instead of strings - bypasses validation (allowed_roles_are_valid compares against a string
# list, so a symbol-serialized row fails it, per InvestorAdvisor#setup_issues's own documented
# legacy-format note) since this fixture exists specifically to construct that otherwise-
# unconstructable-via-the-UI legacy state.
Given('there is an investor advisor grant for {string} on entity {string} with legacy symbol allowed_roles') do |email, entity_kv|
  user   = User.find_by!(email: email)
  entity = Entity.find_by!(name: entity_kv.split('=').last)
  ia = InvestorAdvisor.new(user:, entity:, email: user.email, allowed_roles: [:employee])
  permission_keys = User.permissions.keys
  permission_keys.each { |permission| ia.permissions.set(permission) }
  ia.save!(validate: false)
end

# Stubs InvestorKyc.for_investor_advisor so a scenario can prove show?'s grant branch falls
# through to this check (rather than exclusively denying) without needing to construct a full,
# independent for_investor_advisor-passing fixture (approved InvestorAccess + AccessRight scoped
# to the investor's own entity + a live advisor switch into it) - that scope's own correctness is
# pre-existing and untouched by this change; what's under test here is only whether show? gives it
# a chance to run at all for a grant that doesn't itself qualify.
Given('InvestorKyc.for_investor_advisor is stubbed to return the investor kyc for {string}') do |email|
  user = User.find_by!(email: email)
  allow(InvestorKyc).to receive(:for_investor_advisor) do |called_user, **_kwargs|
    called_user.id == user.id ? InvestorKyc.where(id: @investor_kyc.id) : InvestorKyc.none
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

When('the investor submits the KYC as final') do
  @investor_kyc.reload
  result = InvestorKycUpdate.call(investor_kyc: @investor_kyc, investor_user: true, validate: true, submitted: true)
  expect(result).to be_success
end

Then('the fund admin does not receive a KYC updated notification email') do
  mail = ActionMailer::Base.deliveries.find do |m|
    m.to.include?(@user.email) && m.subject.to_s.downcase.include?('updated')
  end
  expect(mail).to be_nil
end

Then('the user {string} receives exactly one KYC submission notification email') do |email|
  eventually do
    mails = ActionMailer::Base.deliveries.select do |m|
      m.to.include?(email) && m.subject.to_s.downcase.include?('submitted')
    end
    expect(mails.size).to eq(1)
  end
end
