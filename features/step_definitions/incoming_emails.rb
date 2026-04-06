When('we receive an incoming email {string} for the commitments from sendgrid') do |string|
  @commitment = CapitalCommitment.last

  # Parse the input string and remove 'attachment' as it's not a model attribute
  args = string.split(';').map { |s| s.split('=') }.to_h
  attachment_file = args.delete('attachment')
  filtered_string = args.map { |k, v| "#{k}=#{v}" }.join(';')

  # Use factory to build the incoming email data
  @incoming_email_data = FactoryBot.build(:incoming_email, from: "investor@example.com")
  key_values(@incoming_email_data, filtered_string)

  # The 'to' address must match the pattern for set_owner to work
  to_address = "capital_commitment.#{@commitment.id}@dev.caphive.app"

  # Prepare payload for SendGrid POST (multipart/form-data)
  payload = {
    "from" => @incoming_email_data.from,
    "to" => to_address,
    "subject" => @incoming_email_data.subject,
    "text" => @incoming_email_data.body,
    "html" => "<div>#{@incoming_email_data.body}</div>",
    "attachments" => "0"
  }

  if attachment_file.present?
    payload["attachments"] = "1"
    file_path = Rails.public_path.join('sample_uploads', attachment_file)
    payload["attachment1"] = Rack::Test::UploadedFile.new(file_path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  # Use Rack::Test to post to the endpoint
  session = Rack::Test::Session.new(Rack::MockSession.new(Rails.application))
  session.post "/incoming_emails/sendgrid", payload

  expect(session.last_response.status).to eq(200)
end

Then('an incoming email is created for the commitments') do
  @incoming_email = IncomingEmail.last
  expect(@incoming_email).to be_present
  expect(@incoming_email.owner).to eq(@commitment)
end

Then('the documents are attached to the incoming email') do
  expect(@incoming_email.documents.count).to be > 0
end
