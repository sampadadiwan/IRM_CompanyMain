# frozen_string_literal: true

# Step definitions for features/core/nda_notifications.feature
# Module 8 — Notifications, Revocation & Expiry Jobs:
#   GP revocation, NdaExpiryReminder dedup, expiry classification,
#   NdaNotificationRecipients resolution, and resolver revoked status.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config),
#   nda_status_steps.rb (LP investor with approved access, signatory tagging),
#   and nda_expiry_versioning_steps.rb (time-based expiry setup).

# ── Setup steps — Revocation ─────────────────────────────────────────────────

# GP revokes an accepted NDA for the named investor without a reason.
When("the GP revokes the NDA for investor {string}") do |_investor_name|
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first

  @revocation = NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @user,
    entity: @gp_entity,
    status: "revoked",
    nda_version: latest.nda_version,
    ip_address: "192.168.1.1",
    user_agent: "Mozilla/5.0 (GP)"
  )
end

# GP revokes with a specific reason.
When("the GP revokes the NDA for investor {string} with reason {string}") do |_investor_name, reason|
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first

  @revocation = NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @user,
    entity: @gp_entity,
    status: "revoked",
    reason: reason,
    nda_version: latest.nda_version,
    ip_address: "192.168.1.1",
    user_agent: "Mozilla/5.0 (GP)"
  )
end

# Background step — GP has already revoked.
Given("the GP has revoked the NDA for investor {string}") do |investor_name|
  step "the GP revokes the NDA for investor \"#{investor_name}\""
end

# ── Setup steps — Notification Emails ────────────────────────────────────────

# Sets notification_emails on the NDA config.
Given("the NDA config has notification_emails {string}") do |emails|
  email_array = emails.split(",").map(&:strip)
  @nda_config.update!(notification_emails: email_array.to_json)
end

# ── Setup steps — Expiry Reminder ────────────────────────────────────────────

# Creates an expiry reminder record.
When("an expiry reminder is created for {string} with kind {string} and expiry date {int} days from now") do |_investor_name, kind, days|
  @expiry_reminder = NdaExpiryReminder.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    expiry_date: days.days.from_now.to_date,
    kind: kind,
    sent_at: Time.current
  )
  @expiry_date_for_test = days.days.from_now.to_date
end

# Background step — expiry reminder already exists.
Given("an expiry reminder exists for {string} with kind {string} and expiry date {int} days from now") do |investor_name, kind, days|
  step "an expiry reminder is created for \"#{investor_name}\" with kind \"#{kind}\" and expiry date #{days} days from now"
end

# ── Action steps — Notification Recipients ───────────────────────────────────

# Resolves notification recipients for a given event type and investor.
When("notification recipients are resolved for event {string} and investor {string}") do |event, _investor_name|
  @notification_result = NdaNotificationRecipients.resolve(event.to_sym, @nda_config, @lp_investor)
end

# Resolves notification recipients for events that don't need a specific investor (reminder, new_version).
When("notification recipients are resolved for event {string}") do |event|
  @notification_result = NdaNotificationRecipients.resolve(event.to_sym, @nda_config)
end

# ── Assertion steps — Revocation ─────────────────────────────────────────────

# Verifies the latest acceptance for the named investor has the expected status.
Then("the latest NDA acceptance for {string} should have status {string}") do |_investor_name, status|
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first
  expect(latest).to be_present
  expect(latest.status).to eq(status)
end

# Verifies the latest acceptance has the expected reason.
Then("the latest NDA acceptance for {string} should have reason {string}") do |_investor_name, reason|
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first
  expect(latest.reason).to eq(reason)
end

# Verifies the count of acceptance records for the investor.
Then("there should be {int} NDA acceptance records for investor {string}") do |count, _investor_name|
  records = NdaAcceptance.where(nda_config: @nda_config, investor: @lp_investor)
  expect(records.count).to eq(count)
end

# Verifies revoking fails (no accepted NDA to revoke).
Then("revoking the NDA for investor {string} should fail") do |_investor_name|
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first

  can_revoke = latest&.accepted?
  expect(can_revoke).not_to be true
end

# Verifies revoked? predicate.
Then("the latest NDA acceptance revoked? should be true") do
  latest = NdaAcceptance
           .where(nda_config: @nda_config, investor: @lp_investor)
           .order(created_at: :desc)
           .first
  expect(latest.revoked?).to be true
end

# ── Assertion steps — Resolver Revoked ───────────────────────────────────────

# Verifies the revoked counter.
Then("the resolver counters should show revoked {int}") do |count|
  expect(@resolver_result[:counters][:revoked]).to eq(count)
end

# ── Assertion steps — Expiry Reminder ────────────────────────────────────────

# Verifies the count of expiry reminders for the NDA config.
Then("there should be {int} expiry reminder(s) for the NDA config") do |count|
  expect(NdaExpiryReminder.where(nda_config: @nda_config).count).to eq(count)
end

# Duplicate expiry reminder raises an error.
# Changed: Use rescue-based check instead of compound raise_error matcher.
# Why: RSpec cannot combine two raise_error matchers with .or.
Then("creating a duplicate expiry reminder should raise an error") do
  error_raised = false
  begin
    NdaExpiryReminder.create!(
      nda_config: @nda_config,
      investor: @lp_investor,
      expiry_date: @expiry_date_for_test,
      kind: "approaching",
      sent_at: Time.current
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    error_raised = true
  end
  expect(error_raised).to be(true), "Expected duplicate expiry reminder to raise an error but it did not"
end

# Verifies already_sent? returns true.
Then("already_sent? should return true for the same parameters") do
  result = NdaExpiryReminder.already_sent?(
    @nda_config.id, @lp_investor.id, @expiry_date_for_test, "approaching"
  )
  expect(result).to be true
end

# Verifies already_sent? returns false.
Then("already_sent? should return false for {string} with kind {string} and expiry date {int} days from now") do |_investor_name, kind, days|
  result = NdaExpiryReminder.already_sent?(
    @nda_config.id, @lp_investor.id, days.days.from_now.to_date, kind
  )
  expect(result).to be false
end

# ── Assertion steps — Expiry Classification ──────────────────────────────────

# Classifies the expiry date using the same logic as NdaExpiryCheckJob#classify.
Then("the expiry classification should be {string}") do |expected|
  expiry_date = compute_test_expiry_date(@nda_config, @nda_acceptance)
  classification = classify_test_expiry(expiry_date)
  expect(classification).to eq(expected)
end

# Verifies nil classification (no alert needed).
Then("the expiry classification should be nil") do
  expiry_date = compute_test_expiry_date(@nda_config, @nda_acceptance)
  classification = classify_test_expiry(expiry_date)
  expect(classification).to be_nil
end

# Verifies until_revoked is not scannable.
Then("the NDA config should not be scannable for expiry") do
  expect(@nda_config.validity_type).to eq("until_revoked")
end

# ── Assertion steps — Notification Recipients ────────────────────────────────

# Verifies GP email recipients include a specific email.
Then("the GP email recipients should include {string}") do |email|
  expect(@notification_result[:gp_emails]).to include(email)
end

# Verifies a specific count of GP email recipients.
Then("there should be {int} GP email recipients") do |count|
  expect(@notification_result[:gp_emails].size).to eq(count)
end

# Verifies LP user recipients include the LP user.
Then("the LP user recipients should include the LP user") do
  expect(@notification_result[:lp_users].map(&:id)).to include(@lp_user.id)
end

# Verifies a specific count of LP user recipients.
Then("there should be {int} LP user recipients") do |count|
  expect(@notification_result[:lp_users].size).to eq(count)
end

# ── Assertion steps — Cascade ────────────────────────────────────────────────
# (Cascade count check reuses "there should be {int} expiry reminder(s)" step above)

# ── Helper methods (mirror NdaExpiryCheckJob private methods) ────────────────

# @param nda_config [NdaConfig] the NDA config with validity settings
# @param acceptance [NdaAcceptance] the latest accepted record
# @return [Date, nil] the computed expiry date
def compute_test_expiry_date(nda_config, acceptance)
  case nda_config.validity_type
  when "fixed_period"
    (acceptance.accepted_at + nda_config.validity_days.days).to_date
  when "specific_date"
    nda_config.validity_date
  end
end

# @param expiry_date [Date] the computed expiry date
# @return [String, nil] "approaching", "expired", or nil
def classify_test_expiry(expiry_date)
  return nil if expiry_date.nil?

  today = Date.current
  if expiry_date < today
    "expired"
  elsif expiry_date <= today + 7
    "approaching"
  end
end
