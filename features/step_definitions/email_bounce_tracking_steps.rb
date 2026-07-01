# Step definitions for features/core/email_bounce_tracking.feature

# ── Helpers ───────────────────────────────────────────────────────────────────

# Builds a well-formed SES bounce/complaint payload (the "Message" field of the SNS
# envelope) tagged with the given tracking_id, matching the shape ProcessSesNotificationJob
# expects (see docs/features/email_bounce_complaint_detection_prd.md §8.4).
def build_ses_message(notification_type, tracking_id:, recipient_email:, bounce_type: nil, bounce_subtype: nil, complaint_feedback_type: nil, diagnostic_code: "550 5.1.1 user unknown")
  payload = {
    "notificationType" => notification_type,
    "mail" => {
      "messageId" => SecureRandom.uuid,
      "headers" => [{ "name" => "X-CapHive-Tracking-Id", "value" => tracking_id }]
    }
  }

  if notification_type == "Bounce"
    payload["bounce"] = {
      "bounceType" => bounce_type,
      "bounceSubType" => bounce_subtype,
      "timestamp" => Time.current.iso8601,
      "bouncedRecipients" => [{ "emailAddress" => recipient_email, "diagnosticCode" => diagnostic_code }]
    }
  else
    payload["complaint"] = {
      "complaintFeedbackType" => complaint_feedback_type,
      "timestamp" => Time.current.iso8601,
      "complainedRecipients" => [{ "emailAddress" => recipient_email }]
    }
  end

  payload
end

# POSTs an SNS envelope to the webhook via Rack::Test, mirroring the pattern already used
# for the SendGrid webhook in features/step_definitions/incoming_emails.rb.
def post_ses_notification(message_hash:, signing_cert_url: "https://sns.us-east-1.amazonaws.com/fake.pem")
  envelope = {
    "Type" => "Notification",
    "MessageId" => SecureRandom.uuid,
    "TopicArn" => "arn:aws:sns:us-east-1:123456789012:test-topic",
    "Message" => message_hash.to_json,
    "Timestamp" => Time.current.iso8601,
    "SignatureVersion" => "1",
    "Signature" => "fake-signature",
    "SigningCertURL" => signing_cert_url
  }

  session = Rack::Test::Session.new(Rack::MockSession.new(Rails.application))
  session.post "/ses_notifications", envelope.to_json, { "CONTENT_TYPE" => "application/json" }
  session
end

# ── Setup ─────────────────────────────────────────────────────────────────────

Given('I am logged in as an internal admin') do
  @entity = FactoryBot.create(:entity, :with_exchange_rates)
  @user = FactoryBot.create(:user, entity: @entity)
  @user.add_role(:support)
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

# Sends an email through ApplicationMailer with a Noticed::Notification attached (the only
# path that gets tagged for bounce tracking — see ApplicationMailer#tag_for_bounce_tracking).
# Reuses UserMailer#magic_link as the delivery vehicle since the tagging/recording logic
# lives in the shared ApplicationMailer base class, not per-mailer.
Given('a notification-linked email has been sent to {string}') do |email|
  recipient = FactoryBot.create(:user, entity: @entity, email: email)
  event = Noticed::Event.create!(record: @entity, params: { entity_id: @entity.id })
  @notification = Noticed::Notification.create!(recipient: recipient, event: event)

  UserMailer.with(id: recipient.id, notification_id: @notification.id, entity_id: @entity.id).magic_link.deliver_now
  @notification.reload
end

# The counterpart negative case: no notification_id passed, so tag_for_bounce_tracking
# should return early and no headers should be added.
When('a direct mailer email is sent to {string} with no notification') do |email|
  recipient = FactoryBot.create(:user, entity: @entity, email: email)
  ActionMailer::Base.deliveries.clear
  UserMailer.with(id: recipient.id, entity_id: @entity.id).magic_link.deliver_now
end

Given('there is another entity {string} with its own bounced email {string}') do |entity_kv, email|
  other_entity = FactoryBot.build(:entity, :with_exchange_rates)
  key_values(other_entity, entity_kv)
  other_entity.save!

  recipient = FactoryBot.create(:user, entity: other_entity, email: email)
  event = Noticed::Event.create!(record: other_entity, params: { entity_id: other_entity.id })
  notification = Noticed::Notification.create!(recipient: recipient, event: event)

  UserMailer.with(id: recipient.id, notification_id: notification.id, entity_id: other_entity.id).magic_link.deliver_now
  notification.reload

  payload = build_ses_message("Bounce", tracking_id: notification.tracking_id, recipient_email: email, bounce_type: "Permanent", bounce_subtype: "General")
  response = post_ses_notification(message_hash: payload)
  expect(response.last_response.status).to eq(200)
end

Given('there is an InvestorAccess record with email {string} for my entity') do |email|
  # investor_entity explicitly overridden — the :investor factory otherwise samples a
  # random Entity.startups entity, which can be nil/absent in an otherwise-empty test DB.
  investor = @entity.investors.first || FactoryBot.create(:investor, entity: @entity, investor_entity: @entity)
  @investor_access = FactoryBot.create(:investor_access, email: email, entity: @entity, investor: investor, investor_entity: @entity, user: @user, email_enabled: true)
end

# ── When ──────────────────────────────────────────────────────────────────────

When('SES reports a bounce for that email') do
  payload = build_ses_message("Bounce", tracking_id: @notification.tracking_id, recipient_email: @notification.recipient.email, bounce_type: "Permanent", bounce_subtype: "General")
  @last_ses_response = post_ses_notification(message_hash: payload)
  expect(@last_ses_response.last_response.status).to eq(200)
end

When('SES reports a complaint for that email') do
  payload = build_ses_message("Complaint", tracking_id: @notification.tracking_id, recipient_email: @notification.recipient.email, complaint_feedback_type: "abuse")
  @last_ses_response = post_ses_notification(message_hash: payload)
  expect(@last_ses_response.last_response.status).to eq(200)
end

When('an unsigned SNS bounce notification is posted to the webhook') do
  payload = build_ses_message("Bounce", tracking_id: "does-not-matter", recipient_email: "nobody@example.com", bounce_type: "Permanent")
  # Not hosted at an *.amazonaws.com URL — fails Aws::SNS::MessageVerifier's AWS-hostname
  # check locally, with no network call, so this stays deterministic in CI.
  @last_ses_response = post_ses_notification(message_hash: payload, signing_cert_url: "https://evil.example.com/fake.pem")
end

When('I visit the email bounce events report') do
  visit email_bounce_events_path
end

# ── Then ──────────────────────────────────────────────────────────────────────

Then('the notification should show a bounced status') do
  @notification.reload
  expect(@notification.bounced_at).to be_present
  expect(@notification.bounce_type).to eq("Permanent")
end

Then('no tracking headers should be present on the sent email') do
  mail = ActionMailer::Base.deliveries.last
  expect(mail["X-CapHive-Tracking-Id"]).to be_nil
end

Then('the webhook should respond with status {int}') do |status|
  expect(@last_ses_response.last_response.status).to eq(status)
end

Then('I should see {string} in the email bounce events table') do |text|
  within("table#email_bounce_events") do
    expect(page).to have_content(text)
  end
end

Then('I should not see {string} in the email bounce events table') do |text|
  within("table#email_bounce_events") do
    expect(page).not_to have_content(text)
  end
end

Then('the InvestorAccess record for {string} should have email disabled') do |email|
  access = InvestorAccess.find_by!(email: email)
  expect(access.email_enabled).to be false
  expect(access.audits.last.action).to eq("update")
  expect(access.audits.last.audited_changes["email_enabled"]).to eq([true, false])
end
