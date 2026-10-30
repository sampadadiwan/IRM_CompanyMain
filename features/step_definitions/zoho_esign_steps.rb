# Zoho-specific eSign step definitions: expiry/reminder display, extending an already-sent
# request's expiry, and the webhook signature check. Mirrors the Docusign/Digio esign step
# patterns in investor.rb, scoped to zoho_esign.feature / zoho_esign_webhook.feature.
# Zoho itself is stubbed at ZohoSignClient (the only class that talks HTTP to Zoho).

Then('the document has {string} e_signatures by Zoho') do |_string|
  stub_zoho_sign_client
  @doc = Document.order(:created_at).last
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Send For eSignatures")
  expect(page).to have_content("was queued for eSignature")
  visit(document_path(@doc))
end

Then('the document shows its Zoho eSignature expiry and reminder details') do
  @doc.reload
  visit(document_path(@doc))
  expect(page).to have_content("eSignature Expires On")
  expect(page).to have_content(I18n.l(@doc.esign_expires_at.to_date))
  expect(page).to have_content("eSignature Reminders")
  expect(page).to have_content("Every #{ZohoEsignHelper::DEFAULT_REMINDER_PERIOD_DAYS} day(s)")
end

Then('the Zoho eSignature expiry is extended to a valid future date') do
  new_expiry = Date.tomorrow + 10.days
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Extend Expiry")
  within("#extendExpiryModal") do
    fill_in("expire_by", with: new_expiry)
    click_on("Extend Expiry")
  end

  expect(page).to have_content("Document's eSignature expiry was extended")
  expect(@doc.reload.esign_expires_at.to_date).to eq(new_expiry)
end

# The expiry field is a native HTML5 date input, so a real browser won't submit a malformed value -
# exercise the guard on the same code path the controller calls instead.
Then('extending the Zoho eSignature expiry with an invalid date is rejected without raising') do
  original_expiry = @doc.reload.esign_expires_at
  result = nil
  expect { result = EsignHelper.new(@doc).extend_expiry("not-a-real-date") }.not_to raise_error
  expect(result.success?).to be(false)
  expect(result.errors).to eq("Choose a date from #{I18n.l(Date.tomorrow)} onward.")
  expect(@doc.reload.esign_expires_at).to eq(original_expiry)
end

Given('the Zoho eSign webhook signature verification will fail') do
  allow(ZohoEsignHelper).to receive(:verify_signature).and_return(false)
end

When('a Zoho eSign webhook request is received with an invalid signature') do
  Capybara.current_session # boots the app server when no page has been visited yet
  url = URI.parse("#{Capybara.app_host}/documents/signature_progress")
  http = Net::HTTP.new(url.host, url.port)
  request = Net::HTTP::Post.new(url.path, { 'Content-Type' => 'application/json', 'X-ZS-WEBHOOK-SIGNATURE' => 'invalid-signature' })
  request.body = { notifications: { operation_type: "RequestCompleted" }, requests: { request_id: "does-not-matter" } }.to_json
  @webhook_response = http.request(request)
end

Then('the webhook request is rejected as unauthorized') do
  expect(@webhook_response.code.to_i).to eq(401)
  expect(@webhook_response.body).to include("Invalid signature")
end

Given('the document\'s Zoho expiration is set to {string} days with reminders every {string} days') do |expiration_days, reminder_days|
  @doc.update!(esign_expiration_days: expiration_days.to_i, esign_reminder_period: reminder_days.to_i, esign_email_reminders: true)
end

When('the document is sent for Zoho eSign') do
  stub_zoho_sign_client
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Send For eSignatures")
  expect(page).to have_content("was queued for eSignature")
  visit(document_path(@doc))
end

Then('the Zoho eSign request includes an expiration of {string} days and reminders every {string} days') do |expiration_days, reminder_days|
  expect(@zoho_create_request_body).not_to be_nil
  expect(@zoho_create_request_body.dig(:requests, :expiration_days)).to eq(expiration_days.to_i)
  expect(@zoho_create_request_body.dig(:requests, :reminder_period)).to eq(reminder_days.to_i)
  expect(@zoho_create_request_body.dig(:requests, :email_reminders)).to eq(true)
end

Then('the document is partially signed via Zoho') do
  stub_zoho_sign_client(status: "inprogress", action_statuses: %w[SIGNED YET_TO_SIGN])
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Get eSignatures' updates")
  expect(page).to have_content("Fetching Updates for eSignatures")
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document is signed by Zoho and the completion certificate is attached') do
  stub_zoho_sign_client(status: "completed", action_statuses: %w[SIGNED SIGNED])
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Get eSignatures' updates")
  expect(page).to have_content("Fetching Updates for eSignatures")
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_content("Signed")
  expect(@doc.reload.esign_completed?).to be(true)
  expect(Document.where(owner_tag: "Signature Certificate", from_template_id: @doc.id).count).to eq(1)
end

When('a Zoho eSign webhook reports the first signer as signed') do
  payload = {
    notifications: { operation_type: "RequestSigningSuccess", performed_by_email: @esign1.email },
    requests: { request_id: @doc.reload.provider_doc_id }
  }.to_json

  url = URI.parse("#{Capybara.app_host}/documents/signature_progress")
  http = Net::HTTP.new(url.host, url.port)
  request = Net::HTTP::Post.new(url.path, { 'Content-Type' => 'application/json' })
  request.body = payload
  @webhook_response = http.request(request)
end

Then('the first signer\'s status is updated to signed and the second signer remains pending') do
  expect(@webhook_response.code.to_i).to eq(200)
  expect(@esign1.reload.status).to eq("signed")
  expect(@esign2.reload.status).not_to eq("signed")
end

# Every Zoho call goes through ZohoSignClient; these answer the calls a send and a status check make.
def stub_zoho_sign_client(status: "inprogress", action_statuses: %w[UNOPENED UNOPENED])
  emails = %w[shrikantgour018@gmail.com aseemak56@yahoo.com]
  actions = emails.each_with_index.map { |email, idx| { "action_id" => (9_000 + idx).to_s, "recipient_email" => email, "action_type" => "SIGN" } }
  pdf = Rails.public_path.join("sample_uploads/rta_demo_fund_11_success.pdf").binread
  allow_any_instance_of(ZohoSignClient).to receive(:access_token).and_return("test-access-token")
  allow_any_instance_of(ZohoSignClient).to receive(:create_request) do |_client, data:, file:|
    @zoho_create_request_body = data
    file.read
    { "request_id" => "3z10c1234567890zoho", "document_ids" => [{ "document_id" => "1" }], "actions" => actions }
  end
  allow_any_instance_of(ZohoSignClient).to receive(:submit_request).and_return({ "status" => "success" })
  allow_any_instance_of(ZohoSignClient).to receive(:get_request).and_return(
    { "requests" => { "request_status" => status, "expire_by" => (Time.zone.now + ZohoEsignHelper::DEFAULT_EXPIRATION_DAYS.days).to_i * 1000,
                      "actions" => actions.zip(action_statuses).map { |action, action_status| action.merge("action_status" => action_status) } } }
  )
  allow_any_instance_of(ZohoSignClient).to receive(:extend).and_return({ "status" => "success" })
  allow_any_instance_of(ZohoSignClient).to receive(:download_pdf).and_return(pdf)
  allow_any_instance_of(ZohoSignClient).to receive(:completion_certificate).and_return(pdf)
end
