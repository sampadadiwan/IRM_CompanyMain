# frozen_string_literal: true

# Step definitions for Deal Update Agent authentication scenarios.
# Tests the DealIngestAuthenticator security boundary — address lookup,
# sender verification, SPF/DKIM/DMARC, deduplication, and revocation.

# --- Webhook Invocation ---

When("a SendGrid webhook arrives with:") do |table|
  row = table.rows_hash

  # Resolve dynamic values.
  to_address = case row["to"]
               when "the deal ingest address"
                 @ingest_address.full_address
               else
                 row["to"]
               end

  from_address = case row["from"]
                 when "the user's email"
                   @user.email
                 else
                   row["from"]
                 end

  # Build headers with Message-ID if provided.
  headers = row["headers"] || ""
  if row["message_id"]
    headers += "\nMessage-ID: <#{row['message_id']}>"
  else
    headers += "\nMessage-ID: <#{SecureRandom.uuid}@mail.test>"
  end

  @webhook_params = ActionController::Parameters.new(
    to: to_address,
    from: from_address,
    subject: "Test email",
    text: row["text"],
    html: nil,
    headers: headers,
    envelope: { "from" => from_address, "to" => [to_address] }.to_json
  )

  @auth_result = DealIngestAuthenticator.call(@webhook_params)
end

# --- Preconditions ---

Given("an AgentIngestedEmail already exists with message_id {string}") do |message_id|
  AgentIngestedEmail.create!(
    deal: @deal,
    sender_user: @user,
    message_id: message_id,
    raw_payload: "Previous email",
    received_at: 1.hour.ago,
    status: "filed"
  )
end

Given("the deal ingest address has been revoked") do
  @ingest_address.revoke!
end

# --- Assertions: Records Created ---

Then("an AgentIngestedEmail should be created with status {string}") do |status|
  @ingested_email = AgentIngestedEmail.last
  expect(@ingested_email).not_to be_nil, "Expected an AgentIngestedEmail to exist"
  expect(@ingested_email.status).to eq(status)
  expect(@ingested_email.deal).to eq(@deal)
  expect(@ingested_email.sender_user).to eq(@user)
end

Then("no AgentIngestedEmail should be created") do
  # Exclude any pre-existing records created in Given steps.
  new_emails = AgentIngestedEmail.where(status: "pending")
  expect(new_emails.count).to eq(0),
    "Expected no new AgentIngestedEmail but found #{new_emails.count}"
end

Then("no new AgentIngestedEmail should be created") do
  # Only one should exist (the one from the Given step).
  expect(AgentIngestedEmail.count).to eq(1),
    "Expected exactly 1 AgentIngestedEmail (the pre-existing one) but found #{AgentIngestedEmail.count}"
end

# --- Assertions: Jobs ---

Then("a ProcessDealIngestJob should be enqueued") do
  jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ProcessDealIngestJob }
  expect(jobs).not_to be_empty, "Expected ProcessDealIngestJob to be enqueued but none found"
end

Then("no job should be enqueued") do
  jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ProcessDealIngestJob }
  expect(jobs).to be_empty, "Expected no ProcessDealIngestJob but found #{jobs.count}"
end

# --- Assertions: Emails ---

Then("no email should be sent") do
  expect(ActionMailer::Base.deliveries).to be_empty,
    "Expected no emails but found #{ActionMailer::Base.deliveries.count}"
end
