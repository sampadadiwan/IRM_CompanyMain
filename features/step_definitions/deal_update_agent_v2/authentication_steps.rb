# frozen_string_literal: true

# Step definitions for Deal Update Agent v2 authentication scenarios.
# Tests the access-based auth model: address → deal, From → user,
# check deal access, SPF/DKIM/DMARC, deduplication.

# --- Webhook Invocation ---

When("a v2 SendGrid webhook arrives with:") do |table|
  row = table.rows_hash

  # Resolve dynamic To address.
  to_address = case row["to"]
               when "the deal ingest address"
                 @ingest_address.full_address
               else
                 row["to"]
               end

  # Resolve dynamic From address — supports multiple users.
  from_address = case row["from"]
                 when "the user's email"
                   @user.email
                 when "the second user's email"
                   @users.values.last.email
                 when "the no-access user's email"
                   @users["no_access"].email
                 else
                   row["from"]
                 end

  # Build headers with Message-ID.
  headers = row["headers"] || ""
  headers += if row["message_id"]
               "\nMessage-ID: <#{row['message_id']}>"
             else
               "\nMessage-ID: <#{SecureRandom.uuid}@mail.test>"
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

Given("a v2 AgentIngestedEmail already exists with message_id {string}") do |message_id|
  AgentIngestedEmail.create!(
    deal: @deal,
    sender_user: @user,
    message_id: message_id,
    raw_payload: "Previous email",
    received_at: 1.hour.ago,
    status: "filed"
  )
end

# --- Assertions: Records Created ---

Then("a v2 AgentIngestedEmail should be created with status {string}") do |status|
  @ingested_email = AgentIngestedEmail.last
  expect(@ingested_email).not_to be_nil, "Expected an AgentIngestedEmail to exist"
  expect(@ingested_email.status).to eq(status)
  expect(@ingested_email.deal).to eq(@deal)
end

Then("no v2 AgentIngestedEmail should be created") do
  new_emails = AgentIngestedEmail.where(status: "pending")
  expect(new_emails.count).to eq(0),
                              "Expected no new AgentIngestedEmail but found #{new_emails.count}"
end

Then("no new v2 AgentIngestedEmail should be created") do
  expect(AgentIngestedEmail.count).to eq(1),
                                      "Expected exactly 1 AgentIngestedEmail (the pre-existing one) but found #{AgentIngestedEmail.count}"
end

# --- Assertions: Jobs ---

Then("a v2 ProcessDealIngestJob should be enqueued") do
  jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ProcessDealIngestJob }
  expect(jobs).not_to be_empty, "Expected ProcessDealIngestJob to be enqueued but none found"
end

Then("no v2 job should be enqueued") do
  jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == ProcessDealIngestJob }
  expect(jobs).to be_empty, "Expected no ProcessDealIngestJob but found #{jobs.count}"
end

# --- Assertions: Emails ---

Then("no v2 email should be sent") do
  expect(ActionMailer::Base.deliveries).to be_empty,
                                           "Expected no emails but found #{ActionMailer::Base.deliveries.count}: #{ActionMailer::Base.deliveries.map(&:subject)}"
end

# Webhook invocation with a file attachment.
# Uses Rack::Test::UploadedFile to simulate SendGrid's multipart attachment field.
#
# @param filename [String] file name from public/sample_uploads/
When("a v2 SendGrid webhook arrives with attachment {string}:") do |filename, table|
  row = table.rows_hash

  to_address = case row["to"]
               when "the deal ingest address"
                 @ingest_address.full_address
               else
                 row["to"]
               end

  from_address = case row["from"]
                 when "the user's email"
                   @user.email
                 when "the second user's email"
                   @users.values.last.email
                 else
                   row["from"]
                 end

  headers = row["headers"] || ""
  headers += "\nMessage-ID: <#{SecureRandom.uuid}@mail.test>"

  file_path = Rails.public_path.join("sample_uploads", filename)
  attachment = Rack::Test::UploadedFile.new(file_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

  @webhook_params = ActionController::Parameters.new(
    to: to_address,
    from: from_address,
    subject: "Test email",
    text: row["text"],
    html: nil,
    headers: headers,
    envelope: { "from" => from_address, "to" => [to_address] }.to_json,
    attachment1: attachment
  )

  @auth_result = DealIngestAuthenticator.call(@webhook_params)
end
