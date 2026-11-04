# Zoho eSign steps. Zoho itself is the WebMock fake in features/support/zoho_sign_stub.rb
# (`zoho_fake`), so every scenario using these steps is tagged @zoho-http. Jobs run inline, so a
# click that enqueues a send or a status check has finished by the time the next page renders.

SECOND_SIGNERS = %w[shrikantgour018@gmail.com aseemak56@yahoo.com].freeze

# A 3-page PDF owned by an investor (the signed copy and certificate are filed in the owner's folder).
Given('there is an approved Zoho document {string}') do |name|
  zoho_fake
  steps %(Given there is an existing investor "entity_type=Family Office")
  @doc = Document.create!(entity: @entity, user: @user, owner: @investor, folder: @investor.document_folder, name:, approved: true,
                          file: Rails.public_path.join("sample_uploads/rta_demo_fund_11_success.pdf").open)
end

Given('the document is to be signed by {string}') do |emails|
  emails.split(",").map(&:strip).each_with_index do |email, idx|
    FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email:, position: idx + 1, signature_type: nil)
  end
end

Given('the signer {string} is set to sign with Aadhaar') do |email|
  @doc.e_signatures.find_by!(email:).update!(signature_type: "Aadhaar")
end

Given('the document has a stamp paper') do
  @doc.entity.entity_setting.update!(stamp_paper_tags: "GJ-100")
  StampPaper.create!(owner: @doc, tags: "GJ-100:1", sign_on_page: "LAST", note_on_page: "LAST")
end

Given('the document has {int} Zoho signers') do |count|
  count.times { |idx| FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "signer#{idx + 1}@example.com", position: idx + 1, signature_type: nil) }
end

Given('the document places signature boxes on the {string} page') do |display_on_page|
  @doc.update!(display_on_page:)
end

Given('the document forces the signing order') do
  @doc.update!(force_esign_order: true)
end

Given('the document\'s Zoho expiry and reminder period are blank') do
  @doc.update!(esign_expiration_days: nil, esign_reminder_period: nil, esign_email_reminders: true)
end

Given('the document\'s file is not a PDF') do
  @doc.file = Rails.public_path.join("img/whatsappQR.png").open
  @doc.save!(validate: false)
end

Given('Zoho will time out on {string}') do |op|
  zoho_fake.refuse(op.to_sym, timeout: true)
end

Given('Zoho will refuse {string} with status {int}') do |op, status|
  zoho_fake.refuse(op.to_sym, status:)
end

Given('Zoho reports {string} as {string}') do |email, action_status|
  zoho_fake.signer_status(email, action_status)
end

Given('Zoho reports the request as {string}') do |request_status|
  zoho_fake.request_status = request_status
end

Given('Zoho reports the expiry as {string}') do |date|
  zoho_fake.expire_by = Time.zone.parse(date)
end

Then('the document has {string} e_signatures by Zoho') do |_count|
  @doc ||= Document.order(:created_at).last
  SECOND_SIGNERS.each_with_index do |email, idx|
    FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email:, position: idx + 1, signature_type: nil) unless @doc.e_signatures.exists?(email:)
  end
  steps %(When the document is sent for Zoho eSign)
end

When('the document is sent for Zoho eSign') do
  zoho_fake
  allow(UserAlert).to receive(:new).and_call_original
  @doc ||= Document.order(:created_at).last
  SECOND_SIGNERS.each_with_index { |email, idx| FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email:, position: idx + 1, signature_type: nil) } if @doc.e_signatures.reload.none?
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Send For eSignatures")
  expect(page).to have_content("was queued for eSignature")
  @doc.reload
end

When('the user fetches the eSignature updates') do
  allow(UserAlert).to receive(:new).and_call_original
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Get eSignatures' updates")
  expect(page).to have_content("Fetching Updates for eSignatures")
  @doc.reload
end

When('the daily eSign status check runs') do
  DocumentEsignUpdateJob.new.perform(nil, nil)
  @doc.reload
end

Then('the Zoho request was created at {string}') do |host|
  expect(zoho_fake.calls_to(:create).map(&:host)).to eq([host])
end

Then('every Zoho call went to {string} or {string}') do |accounts_host, sign_host|
  expect(zoho_fake.calls.map(&:host).uniq - [accounts_host, sign_host]).to be_empty
end

Then('nothing was sent to Zoho') do
  expect(zoho_fake.calls_to(:create)).to be_empty
end

Then('the Zoho draft was deleted') do
  expect(zoho_fake.calls_to(:delete).size).to eq(1)
end

Then('Zoho was asked {int} times for the request') do |count|
  expect(zoho_fake.calls_to(:get).size).to eq(count)
end

Then('the document\'s eSign status is {string}') do |status|
  expect(@doc.reload.esign_status).to eq(status)
end

Then('the signer {string} has eSign status {string}') do |email, status|
  expect(@doc.e_signatures.find_by!(email:).status.to_s).to eq(status)
end

Then('the document\'s eSign expiry date is {string}') do |date|
  expected = zoho_relative_date(date)
  expect(@doc.reload.esign_expires_at.to_date).to eq(expected.is_a?(Date) ? expected : Date.parse(expected))
end

Then('the sender is alerted with {string}') do |message|
  expect(UserAlert).to have_received(:new).with(hash_including(message: a_string_including(message))).at_least(:once)
end

Then('the document can be sent again') do
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_button("Re-Send for eSignatures")
end

Then('the Zoho response with {string} is in the eSign log') do |value|
  expect(@doc.reload.esign_log.manual_update_data.to_json).to include(value)
end

Then('the Zoho request is sequential with signing orders {string}') do |orders|
  data = zoho_fake.created_data["requests"]
  expect(data["is_sequential"]).to be(true)
  expect(data["actions"].pluck("signing_order")).to eq(orders.split(",").map(&:to_i))
end

Then('each signer gets a signature box on pages {string}') do |pages|
  expected = pages.split(",").map { |p| p.to_i - 1 }
  actions = zoho_fake.submitted_actions
  actions.each { |action| expect(action["fields"].pluck("page_no")).to eq(expected) }
  expect(actions.map { |a| a["fields"].first["y_coord"] }.uniq.size).to eq(actions.size)
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
  expect(zoho_fake.calls_to(:extend)).to be_empty
end

Given('the Zoho eSign webhook signature verification will fail') do
  allow(ZohoEsignHelper).to receive(:verify_signature).and_return(false)
end

When('a Zoho eSign webhook request is received with an invalid signature') do
  payload = { notifications: { operation_type: "RequestCompleted" }, requests: { request_id: "does-not-matter" } }
  zoho_signed_post("/documents/signature_progress", payload, "invalid-secret")
end

Then('the webhook request is rejected as unauthorized') do
  expect(@webhook_response.code.to_i).to eq(401)
  expect(@webhook_response.body).to include("Invalid signature")
end

Given('the document\'s Zoho expiration is set to {string} days with reminders every {string} days') do |expiration_days, reminder_days|
  @doc ||= Document.order(:created_at).last
  @doc.update!(esign_expiration_days: expiration_days.to_i, esign_reminder_period: reminder_days.to_i, esign_email_reminders: true)
end

Then('the Zoho eSign request includes an expiration of {string} days and reminders every {string} days') do |expiration_days, reminder_days|
  data = zoho_fake.created_data
  expect(data).not_to be_nil
  expect(data.dig("requests", "expiration_days")).to eq(expiration_days.to_i)
  expect(data.dig("requests", "reminder_period")).to eq(reminder_days.to_i)
  expect(data.dig("requests", "email_reminders")).to eq(true)
end

Then('the document is partially signed via Zoho') do
  zoho_fake.signer_status(SECOND_SIGNERS[0], "SIGNED")
  zoho_fake.signer_status(SECOND_SIGNERS[1], "YET_TO_SIGN")
  steps %(When the user fetches the eSignature updates)
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document is signed by Zoho and the completion certificate is attached') do
  zoho_fake.request_status = "completed"
  SECOND_SIGNERS.each { |email| zoho_fake.signer_status(email, "SIGNED") }
  steps %(When the user fetches the eSignature updates)
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_content("Signed")
  expect(@doc.reload.esign_completed?).to be(true)
  expect(Document.where(owner_tag: "Signature Certificate", from_template_id: @doc.id).count).to eq(1)
  expect(Document.where(owner_tag: "Signed", from_template_id: @doc.id).count).to eq(1)
end

When('a Zoho eSign webhook reports the first signer as signed') do
  payload = { notifications: { operation_type: "RequestSigningSuccess", performed_by_email: @doc.e_signatures.order(:position).first.email },
              requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post("/documents/signature_progress", payload, nil)
end

Then('the first signer\'s status is updated to signed and the second signer remains pending') do
  first, second = @doc.e_signatures.order(:position).to_a
  expect(@webhook_response.code.to_i).to eq(200)
  expect(first.reload.status).to eq("signed")
  expect(second.reload.status).not_to eq("signed")
end

Given('CapHive\'s Zoho webhook secret is {string}') do |secret|
  platform = ZohoSignAccount.platform.with(webhook_secret: secret)
  allow(ZohoSignAccount).to receive(:platform).and_return(platform)
end

Given('unsigned Zoho updates are refused as in staging') do
  allow(ZohoEsignHelper).to receive(:unsigned_webhooks_allowed?).and_return(false)
end

Given('the signers have no eSign status yet') do
  @doc.e_signatures.update_all(status: "")
end

Given('both signers have signed in Zoho') do
  @doc.e_signatures.update_all(status: "signed")
  @doc.e_signatures.each { |esign| zoho_fake.signer_status(esign.email, "SIGNED") }
end

Given('background jobs are queued instead of run') do
  ActiveJob::Base.queue_adapter = :test
end

Given('Zoho errors are reported') do
  allow(ErrorReport).to receive(:notify).and_call_original
end

When('Zoho posts {string} for {string} to the shared address signed with {string}') do |operation_type, email, secret|
  payload = { notifications: { operation_type:, performed_by_email: email }, requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post("/documents/signature_progress", payload, secret == "nothing" ? nil : secret)
end

When('Zoho posts {string} to the shared address signed with {string}') do |operation_type, secret|
  steps %(When Zoho posts "#{operation_type}" for "" to the shared address signed with "#{secret}")
end

When('the queued Zoho webhook jobs run') do
  jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ZohoWebhookJob }
  expect(jobs).not_to be_empty
  ActiveJob::Base.queue_adapter = :inline
  jobs.each { |job| ZohoWebhookJob.perform_now(*ActiveJob::Arguments.deserialize(job[:args])) }
end

Then('the webhook response is {int}') do |status|
  expect(@webhook_response.code.to_i).to eq(status)
end

Then('the document has {int} signed copy and {int} signature certificate') do |signed, certificates|
  expect(Document.where(owner_tag: "Signed", from_template_id: @doc.id).count).to eq(signed)
  expect(Document.where(owner_tag: "Signature Certificate", from_template_id: @doc.id).count).to eq(certificates)
end

Then('the Zoho webhook {string} is in the eSign log') do |operation_type|
  expect(@doc.reload.esign_log.webhook_data.to_json).to include(operation_type)
end

Then('the certificate failure is reported') do
  expect(ErrorReport).to have_received(:notify).with(kind_of(ZohoSignClient::Error), hash_including(source: "ZohoEsignHelper completion certificate"))
end

# "D" is today, "D+40" forty days from today - dates stay relative because travel_to doesn't mix
# with browser sessions.
def zoho_relative_date(token)
  match = token.match(/\AD([+-]\d+)?\z/)
  match ? Date.current + match[1].to_i : token
end

Given('the document is out for signature') do
  @doc.update!(sent_for_esign: true, esign_status: "requested", provider_doc_id: ZohoSignFake::REQUEST_ID, esign_expires_at: 30.days.from_now)
end

Given('the document\'s eSign status is set to {string}') do |status|
  @doc.update!(esign_status: status)
end

When('the document\'s eSign expiry is set to {int} days') do |days|
  @save_result = @doc.update(esign_expiration_days: days)
end

When('the document\'s eSign reminder period is set to {int} days') do |days|
  @save_result = @doc.update(esign_reminder_period: days)
end

Then('the document is saved') do
  expect(@save_result).to be(true)
end

Then('the document is not saved and shows {string}') do |message|
  expect(@save_result).to be(false)
  expect(@doc.errors.full_messages.join).to include(message)
end

# Valid dates go through the date picker. A refused value is put into the field as plain text and
# the form submitted without the browser's own date checks - the request a tampered page sends.
When('the user extends the Zoho eSignature expiry to {string}') do |value|
  @expiry_before = @doc.reload.esign_expires_at
  date = zoho_relative_date(value)
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Extend Expiry")
  within("#extendExpiryModal") do
    if date.is_a?(Date) && date > Date.current
      fill_in("expire_by", with: date.iso8601)
      click_on("Extend Expiry")
    else
      raw = date.is_a?(Date) ? date.iso8601 : date
      page.execute_script(<<~JS)
        const form = document.createElement("form");
        form.method = "post";
        form.action = #{extend_esign_expiry_document_path(@doc).to_json};
        const fields = { _method: "patch", expire_by: #{raw.to_json}, authenticity_token: document.querySelector("meta[name=csrf-token]")?.content || "" };
        Object.entries(fields).forEach(([name, value]) => {
          const input = document.createElement("input");
          input.type = "hidden"; input.name = name; input.value = value;
          form.appendChild(input);
        });
        document.body.appendChild(form);
        form.submit();
      JS
    end
  end
end

When('the user sends a Zoho reminder') do
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Send Reminder")
end

When('the user cancels the eSignatures') do
  visit(document_path(@doc))
  click_on("Signatures")
  click_on("Cancel eSignatures")
end

# A request the page no longer offers, sent from the browser the way a tampered page would.
When('the user requests {string} for the document directly') do |action|
  visit(document_path(@doc))
  path = { "extend expiry" => extend_esign_expiry_document_path(@doc, expire_by: (Date.current + 10).iso8601),
           "send reminder" => send_esign_reminder_document_path(@doc) }.fetch(action)
  page.evaluate_script(<<~JS)
    fetch("#{path}", { method: "PATCH", redirect: "manual", headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" } }).then(r => r.status)
  JS
end

Then('the user sees {string}') do |message|
  expect(page).to have_content(message)
end

Then('the user sees the extension refused') do
  expect(page).to have_content("Choose a date from #{I18n.l(Date.tomorrow)} onward.")
end

Then('the document shows eSignature Expires On {string}') do |token|
  visit(document_path(@doc))
  expect(page).to have_content("eSignature Expires On")
  expect(page).to have_content(I18n.l(zoho_relative_date(token)))
end

Then('the document\'s eSign expiry is unchanged') do
  expect(@doc.reload.esign_expires_at.to_i).to eq(@expiry_before.to_i)
end

Then('Zoho was asked to {string} {int} time(s)') do |op, count|
  expect(zoho_fake.calls_to(op.to_sym).size).to eq(count)
end

Then('Zoho was not asked to {string}') do |op|
  expect(zoho_fake.calls_to(op.to_sym)).to be_empty
end

Then('the Zoho-only eSign actions are not offered') do
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_no_button("Send Reminder")
  expect(page).to have_no_button("Extend Expiry")
  expect(page).to have_no_content("eSignature Expires On")
  visit(edit_document_path(@doc))
  expect(page).to have_no_content("eSign Expires In (days)")
  expect(page).to have_no_content("eSign Reminder Every (days)")
end

Then('the Send Reminder button is not offered') do
  visit(document_path(@doc))
  click_on("Signatures")
  expect(page).to have_no_button("Send Reminder")
end

Given('Zoho will refuse {string} with error {string}') do |op, error|
  zoho_fake.refuse(op.to_sym, error:)
end
