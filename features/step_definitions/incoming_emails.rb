# Shared helper: builds a SendGrid-style multipart payload and POSTs it to the sendgrid endpoint.
# Returns the Rack::Test response.
def post_to_sendgrid(to:, from:, subject:, body:, message_id: nil, attachments: {})
  headers_string = "Content-Type: text/plain\n"
  headers_string += "Message-ID: <#{message_id}>\n" if message_id.present?

  payload = {
    "from"        => from,
    "to"          => to,
    "subject"     => subject,
    "text"        => body,
    "html"        => "<div>#{body}</div>",
    "headers"     => headers_string,
    "attachments" => attachments.size.to_s
  }

  attachments.each do |key, file|
    payload[key] = file
  end

  session = Rack::Test::Session.new(Rack::MockSession.new(Rails.application))
  session.post "/incoming_emails/sendgrid", payload
  session
end

# ─── Steps used by incoming_email.feature ────────────────────────────────────

Given('there is an incoming email addressed to this investor from {string} with subject {string}') do |from, subject|
  @last_message_id = nil
  @last_session = post_to_sendgrid(
    to:      @investor.incoming_email_address,
    from:    from,
    subject: subject,
    body:    "Test email body"
  )
  expect(@last_session.last_response.status).to eq(200)
end

Given('there is an incoming email addressed to this investor from {string} with subject {string} and attachment {string}') do |from, subject, filename|
  file_path = Rails.public_path.join("sample_uploads", filename)
  attachments = { "attachment1" => Rack::Test::UploadedFile.new(file_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") }
  @last_session = post_to_sendgrid(
    to:          @investor.incoming_email_address,
    from:        from,
    subject:     subject,
    body:        "Test email body",
    attachments: attachments
  )
  expect(@last_session.last_response.status).to eq(200)
end

Given('there is an incoming email addressed to this investor from {string} with subject {string} and message id {string}') do |from, subject, message_id|
  @last_message_id = message_id
  @last_sendgrid_payload = { to: @investor.incoming_email_address, from: from, subject: subject, body: "Test body", message_id: message_id }
  @last_session = post_to_sendgrid(**@last_sendgrid_payload)
  expect(@last_session.last_response.status).to eq(200)
end

Given('the same SendGrid payload is submitted again') do
  expect(@last_sendgrid_payload).to be_present, "No previous SendGrid payload recorded — call the previous step first"
  @last_session = post_to_sendgrid(**@last_sendgrid_payload)
  expect(@last_session.last_response.status).to eq(200)
end

Then('the email should be linked to the investor') do
  incoming = IncomingEmail.last
  expect(incoming).to be_present
  expect(incoming.owner).to eq(@investor)
end

Then('the email should have {int} document(s) attached') do |count|
  incoming = IncomingEmail.last
  expect(incoming.documents.count).to eq(count)
end

Then('only {int} incoming email record(s) should exist with subject {string}') do |count, subject|
  expect(IncomingEmail.where(subject: subject).count).to eq(count)
end

# ─── Steps used by commitments feature ───────────────────────────────────────

When('we receive an incoming email {string} for the commitments from sendgrid') do |string|
  @commitment = CapitalCommitment.last

  args = string.split(';').map { |s| s.split('=') }.to_h
  attachment_file = args.delete('attachment')

  @incoming_email_data = FactoryBot.build(:incoming_email, from: "investor@example.com")
  key_values(@incoming_email_data, args.map { |k, v| "#{k}=#{v}" }.join(';'))

  to_address = "capital_commitment.#{@commitment.id}@dev.caphive.app"
  attachments = {}

  if attachment_file.present?
    file_path = Rails.public_path.join('sample_uploads', attachment_file)
    attachments["attachment1"] = Rack::Test::UploadedFile.new(file_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  @last_session = post_to_sendgrid(
    to:          to_address,
    from:        @incoming_email_data.from,
    subject:     @incoming_email_data.subject,
    body:        @incoming_email_data.body,
    attachments: attachments
  )

  expect(@last_session.last_response.status).to eq(200)
end

Then('an incoming email is created for the commitments') do
  @incoming_email = IncomingEmail.last
  expect(@incoming_email).to be_present
  expect(@incoming_email.owner).to eq(@commitment)
end

Then('the documents are attached to the incoming email') do
  expect(@incoming_email.documents.count).to be > 0
end
