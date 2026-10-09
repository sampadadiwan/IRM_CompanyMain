# Steps for: features/core/investor_kyc_notification_delivery.feature
#
# These build an InvestorKycNotifier event + notification directly (mirroring the
# Noticed::Event.create! / Noticed::Notification.create! pattern already used in
# features/step_definitions/email_bounce_tracking_steps.rb) and call #email_enabled
# on it, instead of asserting on ActionMailer::Base.deliveries - BaseNotifier's
# deliver_by :email skips email_enabled entirely in Rails.env.test?, so a real send
# can never exercise this gate.

When('I build a KYC updated notification for {string}') do |email|
  recipient = User.find_by!(email: email)
  event = InvestorKycNotifier.with(
    record: @investor_kyc, entity_id: @investor_kyc.entity_id,
    email_method: "notify_kyc_updated", msg: "KYC updated for #{@investor_kyc.full_name}",
    user_id: recipient.id
  )
  event.save!
  @built_notification = InvestorKycNotifier::Notification.create!(event:, recipient:)
end

# Same pattern as above, for DocumentNotifier - used to prove the investor_advisor_show_enabled
# gate in email_enabled is scoped to the recipient's grant on the model's OWN entity, not a bare
# role check, so it can't leak into an unrelated notifier via a policy whose #show? is true for
# reasons that have nothing to do with any advisor grant (e.g. DocumentPolicy's public_visibility).
When('I build a document notification for {string}') do |email|
  recipient = User.find_by!(email: email)
  event = DocumentNotifier.with(
    record: @doc_record, entity_id: @doc_record.entity_id,
    email_method: "notify_new_document", msg: nil, user_id: recipient.id
  )
  event.save!
  @built_notification = DocumentNotifier::Notification.create!(event:, recipient:)
end

# email_method is a Symbol on a direct call but a String once it has crossed a job boundary;
# InvestorKycNotifier#url branches on it, so it is built here as the String an enqueued
# notification actually carries.
When('I build a KYC notification for {string} with email_method {string}') do |email, email_method|
  recipient = User.find_by!(email: email)
  event = InvestorKycNotifier.with(
    record: @investor_kyc, entity_id: @investor_kyc.entity_id,
    email_method: email_method, msg: "KYC #{email_method}", user_id: recipient.id
  )
  event.save!
  @built_notification = InvestorKycNotifier::Notification.create!(event:, recipient:)
end

Then('the notification url should be the editable KYC form') do
  expect(@built_notification.url).to include("/edit")
end

Then('the notification url should be the read-only KYC page') do
  expect(@built_notification.url).not_to include("/edit")
end

Then('email_enabled should be true for the notification') do
  # truthy, not strictly `true` - the OR chain in email_enabled can short-circuit through a
  # nil (e.g. `investor_access&.email_enabled`), and deliver_by's `if:` only cares about
  # Ruby truthiness, same as this assertion.
  expect(@built_notification.email_enabled).to be_truthy
end

Then('email_enabled should be false for the notification') do
  expect(@built_notification.email_enabled).to be_falsey
end

# ─────────────────────────────────────────────────────────────────────────────
# investor_advisor_show_enabled error handling (config/initializers/noticed.rb)
# ─────────────────────────────────────────────────────────────────────────────

Given('InvestorKycPolicy#show? raises an error') do
  allow_any_instance_of(InvestorKycPolicy).to receive(:show?).and_raise(RuntimeError, "simulated policy bug")
end

# Pundit.policy! is what investor_advisor_show_enabled calls; this is how it behaves for a model
# that has no policy class at all.
Given('no Pundit policy can be found') do
  allow(Pundit).to receive(:policy!).and_raise(Pundit::NotDefinedError, "unable to find policy")
end

Given('error reports are being watched') do
  allow(ExceptionNotifier).to receive(:notify_exception)
end

Then('the error should have been reported') do
  expect(ExceptionNotifier).to have_received(:notify_exception).with(an_instance_of(RuntimeError), anything)
end

Then('no error should have been reported') do
  expect(ExceptionNotifier).not_to have_received(:notify_exception)
end

# The ExceptionNotifier data must be enough to troubleshoot from the email alone (design.md X1):
# what happened, the record, who missed the email and where they were switched in, their grant,
# the policy, and a console line that re-raises the error.
Then('the error report should let us troubleshoot it for {string}') do |email|
  recipient = User.find_by!(email: email)
  grant = InvestorAdvisor.find_by!(user: recipient, entity: @investor_kyc.entity)
  expect(ExceptionNotifier).to have_received(:notify_exception) do |_error, options|
    report = options[:data]
    expect(report[:summary]).to include("InvestorKycPolicy#show? raised RuntimeError", "InvestorKyc##{@investor_kyc.id}")
    expect(report[:impact]).to include("Only this recipient")
    expect(report[:reproduce]).to eq("Pundit.policy!(User.find(#{recipient.id}), InvestorKyc.find(#{@investor_kyc.id})).show?")
    expect(report[:notification]).to include(notifier: "InvestorKycNotifier", email_method: "notify_kyc_updated")
    expect(report[:record][:entity]).to include(@investor_kyc.entity.name)
    expect(report[:recipient]).to include(id: recipient.id, email: email)
    expect(report[:recipient][:switched_into]).to include(recipient.entity.name)
    expect(report[:advisor_grant]).to include(id: grant.id, enable_kycs: true)
    expect(report[:policy]).to eq("InvestorKycPolicy")
    # No section failed to gather - a "could not be gathered" string means the report itself broke.
    expect(report.values.grep(/could not be gathered/)).to be_empty
  end
end
