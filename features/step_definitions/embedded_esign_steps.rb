# Embedded eSigning (openspec/changes/embedded-esign-digio).
# Shared setup of design.md#worked-examples: Orion Capital sent the Subscription Agreement for eSignature to
# Priya (investor, signer 1), Rahul (employee, signer 2) and Vikram (external, signer 3), signing order on.

ESIGN_SIGNERS = [
  { key: :priya, name: "Priya", email: "priya@lpfund.com", label: "Investor Signatory", position: 1 },
  { key: :rahul, name: "Rahul", email: "rahul@orioncap.com", label: "Fund Signatory", position: 2 },
  { key: :vikram, name: "Vikram", email: "vikram@lawfirm.in", label: "Counsel", position: 3 }
].freeze

ESIGN_DIGIO_DOC_ID = "DID2312191801389959UDGNBWGRGCSC1".freeze

def esign_document_for(entity_name)
  (@esign_documents ||= {})[entity_name] || @document
end

# Creates an approved, publicly visible document that has been sent for eSignature through Digio.
def esign_create_agreement(entity:, owner:, name:, signers:, ordered: true, provider_doc_id: ESIGN_DIGIO_DOC_ID)
  document = FactoryBot.create(:document, entity:, user: owner, name:, folder: entity.folders.first || Folder.first)
  document.update_columns(public_visibility: true, approved: true, sent_for_esign: true, sent_for_esign_date: Time.zone.now,
                          esign_status: "requested", force_esign_order: ordered, provider_doc_id:)
  signers.each do |signer|
    # Creating a signer resets its status, so set "requested" afterwards: the state once Digio has the request
    ESignature.create!(document:, entity:, email: signer[:email], label: signer[:label], position: signer[:position],
                       signature_type: "aadhaar").update_columns(status: "requested")
  end
  document.reload
end

Given('Orion Capital has sent the {string} for eSignature to Priya, Rahul and Vikram') do |document_name|
  @entity = FactoryBot.create(:entity, name: "Orion Capital", entity_type: "Investment Fund", enable_documents: true)
  @entity.enable_embedded_esign = true
  @entity.save!
  @meera = FactoryBot.create(:user, entity: @entity, first_name: "Meera", last_name: "Admin")
  @meera.add_role :company_admin
  @rahul = FactoryBot.create(:user, entity: @entity, first_name: "Rahul", last_name: "Signer", email: "rahul@orioncap.com")
  @lp_entity = FactoryBot.create(:entity, name: "Priya Family Trust", entity_type: "Investor", enable_documents: true)
  @priya = FactoryBot.create(:user, entity: @lp_entity, first_name: "Priya", last_name: "Signer", email: "priya@lpfund.com")

  @document = esign_create_agreement(entity: @entity, owner: @meera, name: document_name, signers: ESIGN_SIGNERS)
  @esign_documents = { "Orion Capital" => @document }
end

Given('the agreement does not enforce a signing order') do
  @document.update_columns(force_esign_order: false)
end

Given('Embedded eSigning is {string} for Orion Capital') do |state|
  @entity.reload
  @entity.enable_embedded_esign = (state == "on")
  @entity.save!
end

Given('the signer {string} is stored with the email {string}') do |current_email, stored_email|
  ESignature.find_by!(document: @document, email: current_email).update_columns(email: stored_email)
end

Given('Priya has signed') do
  ESignature.find_by!(document: @document, position: 1).update_columns(status: "signed")
end

Given('the agreement was cancelled') do
  @document.update_columns(esign_status: "cancelled")
end

Given('Rahul is a company admin at Orion Capital') do
  @rahul.add_role :company_admin
end

Given('Other Co has a similar agreement sent to Priya with Embedded eSigning off') do
  other = FactoryBot.create(:entity, name: "Other Co", entity_type: "Investment Fund", enable_documents: true)
  other_owner = FactoryBot.create(:user, entity: other)
  other_doc = esign_create_agreement(entity: other, owner: other_owner, name: "Other Co Agreement",
                                     signers: [ESIGN_SIGNERS.first], provider_doc_id: "DID-OTHER-CO")
  @esign_documents["Other Co"] = other_doc
end

Given('there is another investor user {string}') do |email|
  entity = FactoryBot.create(:entity, entity_type: "Investor", enable_documents: true)
  FactoryBot.create(:user, entity:, email:)
end

# A fresh browser session logged in as the given user, so scenarios can move between signers.
def esign_login_as(email)
  Capybara.reset_sessions!
  @user = User.find_by!(email:)
  visit("/users/sign_in")
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: "password")
  click_on("Log In")
  expect(page).not_to have_current_path('/users/sign_in', wait: 15)
  # The landing page's own requests share this session: one still in flight can use up the next page's flash
  page.driver.with_playwright_page { |pw_page| pw_page.wait_for_load_state(state: "networkidle") } if page.driver.respond_to?(:with_playwright_page)
  esign_browser_setup
end

When('I open the agreement as {string}') do |email|
  esign_login_as(email)
  visit document_path(@document)
end

When('I open the agreement of {string} as {string}') do |entity_name, email|
  esign_login_as(email)
  visit document_path(esign_document_for(entity_name))
end

When('a support user impersonates {string} and opens the agreement') do |email|
  target = User.find_by!(email:)
  support_user = FactoryBot.create(:user, entity: FactoryBot.create(:entity, entity_type: "Investment Fund"))
  support_user.add_role :support
  FactoryBot.create(:support_client_mapping, user: support_user, entity: target.entity, enabled: true, enable_user_login: true)

  @esign_session = ActionDispatch::Integration::Session.new(Rails.application)
  integration_sign_in(@esign_session, support_user) # M8 — support answers the two-factor code step
  @esign_session.post "/users/#{target.id}/login_as"
  expect(@esign_session.session[:support_user_id]).to be_present, "impersonation did not start"
  @esign_session.get document_path(@document)
end

Then('I should see the signature banner {string}') do |text|
  expect(page).to have_css("#embedded_sign_banner", text:)
end

Then('the banner should have a {string} button') do |label|
  expect(page).to have_css("#embedded_sign_banner a", text: label)
end

Then('the banner should not have a {string} button') do |label|
  expect(page).to have_css("#embedded_sign_banner")
  expect(page).to have_no_css("#embedded_sign_banner a", text: label)
end

Then('I should not see a signature banner') do
  expect(page).to have_no_css("#embedded_sign_banner")
  expect(page).to have_no_link("Sign now")
end

Then('the impersonated response should not show a signature banner') do
  expect(@esign_session.response.status).to eq(200), "expected 200, got #{@esign_session.response.status}"
  expect(@esign_session.response.body).not_to include("embedded_sign_banner")
  expect(@esign_session.response.body).not_to include("Sign now")
end

Then('the Signatures tab should offer {string} on the row of {string} only') do |label, email|
  own = ESignature.find_by!(document: @document, email:)
  click_on("Signatures")
  within("div#e_signatures") do
    ESignature.where(document: @document).find_each do |row|
      if row.id == own.id
        expect(page).to have_css("#e_signature_#{row.id} a", text: label)
      else
        expect(page).to have_no_css("#e_signature_#{row.id} a", text: label)
      end
    end
  end
end

### Signing page (embedded_esign_page.feature) #################################

# Stands in for Digio's SDK: records what the page does with it, so a scenario can assert on the calls.
DIGIO_STUB_JS = <<~JS.freeze
  window.__digioCalls = [];
  window.Digio = function (options) {
    window.__digioOptions = options;
    window.__digioCalls.push({ type: "new", environment: options.environment, is_iframe: options.is_iframe });
  };
  window.Digio.prototype.init = function () { window.__digioCalls.push({ type: "init" }); };
  window.Digio.prototype.submit = function () {
    window.__digioCalls.push({ type: "submit", args: Array.prototype.slice.call(arguments) });
  };
  window.Digio.prototype.cancel = function () { window.__digioCalls.push({ type: "cancel" }); };
JS

# Routes Digio's script to the stub (or to a failure) and sets the viewport, on the current browser page.
def esign_browser_setup
  return unless page.driver.respond_to?(:with_playwright_page)

  @digio_script_requests = []
  mode = @digio_mode
  requests = @digio_script_requests
  page.driver.with_playwright_page do |pw_page|
    pw_page.set_viewport_size(width: 390, height: 844) if @phone_width
    next unless mode

    pw_page.route("**/sdk/v11/digio.js", lambda { |route, request|
      requests << request.url
      if mode == :missing
        route.fulfill(status: 404, headers: { "content-type" => "text/plain" }, body: "not found")
      else
        route.fulfill(status: 200, headers: { "content-type" => "application/javascript" }, body: DIGIO_STUB_JS)
      end
    })
  end
end

Given('the Digio panel stub is installed') do
  @digio_mode = :stub
end

Given('the Digio script cannot be loaded') do
  @digio_mode = :missing
end

Given('the browser is phone width') do
  @phone_width = true
end

When('I press {string} in the embedded signing flow') do |label|
  click_on(label)
end

When('I open the signing page of {string} as {string}') do |signer_email, viewer_email|
  signature = ESignature.find_by!(document: @document, email: signer_email)
  esign_login_as(viewer_email)
  visit sign_e_signature_path(signature)
end

When('a support user impersonates {string} and requests the signing page') do |email|
  target = User.find_by!(email:)
  signature = ESignature.find_by!(document: @document, email:)
  support_user = FactoryBot.create(:user, entity: FactoryBot.create(:entity, entity_type: "Investment Fund"))
  support_user.add_role :support
  FactoryBot.create(:support_client_mapping, user: support_user, entity: target.entity, enabled: true, enable_user_login: true)

  @esign_session = ActionDispatch::Integration::Session.new(Rails.application)
  integration_sign_in(@esign_session, support_user) # M8 — support answers the two-factor code step
  @esign_session.post "/users/#{target.id}/login_as"
  expect(@esign_session.session[:support_user_id]).to be_present, "impersonation did not start"
  @esign_session.get sign_e_signature_path(signature)
end

Then('the impersonated request should be refused') do
  expect(@esign_session.response.status).to be_between(300, 399)
  expect(URI.parse(@esign_session.response.location).path).to eq("/")
end

Then('I should see the signing page for {string} signing as {string}') do |document_name, email|
  expect(page).to have_css("h1", text: document_name)
  expect(page).to have_css("#signing_as", text: email)
end

Then('I should see the signer place {string} and the method {string}') do |place, method|
  expect(page).to have_css("#signer_place", text: place)
  expect(page).to have_css("#signature_method", text: method)
end

Then('I should see the buttons {string} and {string}') do |first, second|
  expect(page).to have_button(first).or have_link(first)
  expect(page).to have_link(second).or have_button(second)
end

Then('I should not see the button {string}') do |label|
  expect(page).to have_no_button(label)
end

Then('I should see the signing message {string}') do |text|
  expect(page).to have_css("#signing_message", text:)
end

Then('I should be refused with {string}') do |text|
  expect(page).to have_content(text)
  expect(page).to have_no_css("#start_signing")
end

Then('the Digio panel should have been started with document {string} and signer {string}') do |document_id, email|
  calls = page.evaluate_script("window.__digioCalls")
  expect(page).to have_css("#start_signing", visible: :all) # still on the signing page
  types = Array(calls).pluck("type")
  expect(types).to eq(%w[new init submit]), "expected new, init, submit; got #{types.inspect}"
  submit = Array(calls).find { |c| c["type"] == "submit" }
  expect(submit["args"]).to eq([document_id, email]), "submit must carry exactly the document id and the email, got #{submit['args'].inspect}"
end

Then('the Digio panel should have been created for the {string} environment in an iframe') do |environment|
  created = Array(page.evaluate_script("window.__digioCalls")).find { |c| c["type"] == "new" }
  expect(created["environment"]).to eq(environment)
  expect(created["is_iframe"]).to eq(true)
end

Then('Digio\'s script should have been requested from {string}') do |url|
  expect(page).to have_css("#start_signing")
  # The page injects the script on connect, so the request is made just after the page is ready
  deadline = Time.zone.now + 10
  sleep 0.1 until @digio_script_requests.include?(url) || Time.zone.now > deadline
  expect(@digio_script_requests).to include(url)
end

Then('the page should offer {string} again') do |label|
  expect(page).to have_button(label)
end

When('the agreement is sent to Digio') do
  captured = nil
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api) do |_helper, body, _token|
    captured = body
    { "id" => "DID-SENT-1" }
  end
  DigioEsignHelper.new.send_document_for_esign(@document)
  @digio_request_body = captured
end

Then('the request to Digio should not ask for an access token') do
  expect(@digio_request_body).to be_present
  expect(@digio_request_body[:generate_access_token]).to eq(false)
end

Then('I should not see the text {string}') do |text|
  expect(page).to have_no_content(text)
end

### Digio notifications (esign_webhook_events.feature) ##########################

# Shapes follow public/digio docs/webhook.txt: top-level event, payload.document, no signing_parties on a
# rejection or a failure.
def digio_notification(event:, document:)
  { entities: ["document"], payload: { document: }, created_at: 1_684_496_220_000,
    id: "WHN230519170700329DEIO1NSND4O17S", event: }.compact.to_json
end

def digio_signing_parties(statuses)
  statuses.map do |email, status|
    { identifier: email, name: email, status:, reason: "esign", type: "self", signature_type: "aadhaar" }
  end
end

# doc.signed (or any event name) with a list of signers
def digio_callback_signed(statuses, event: "doc.signed", document_id: ESIGN_DIGIO_DOC_ID)
  digio_notification(event:, document: { id: document_id, file_name: "Subscription Agreement.pdf", agreement_status: "requested",
                                         signing_parties: digio_signing_parties(statuses),
                                         others: { has_all_signed: statuses.values.all?("signed") } })
end

def digio_callback_no_event(statuses)
  digio_callback_signed(statuses, event: nil)
end

def digio_callback_unknown_event(statuses)
  digio_callback_signed(statuses, event: "doc.expired")
end

def digio_callback_failed(email, code)
  digio_notification(event: "doc.sign.failed",
                     document: { id: ESIGN_DIGIO_DOC_ID, error_message: "UIDAI Server Down", validation_results: nil,
                                 signer_identifier: email, error_code: code, others: nil })
end

# What Digio sends: signer_identifier, no signing_parties, error_code null
def digio_callback_rejected(email, event: "doc.sign.rejected", document_id: ESIGN_DIGIO_DOC_ID)
  digio_notification(event:, document: { id: document_id, error_message: nil, error_code: nil, signer_identifier: email,
                                         validation_results: { overallResult: "FAIL", ruleResults: [] }, others: nil })
end

# A rejection payload that explicitly carries no signer list
def digio_callback_rejected_no_parties(email)
  digio_callback_rejected(email).then { |json| JSON.parse(json).tap { |h| h["payload"]["document"]["signing_parties"] = nil }.to_json }
end

def esign_post_notification(json)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/documents/signature_progress", params: json,
                                                headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  @esign_response = session.response
end

def esign_statuses_from(table)
  table.hashes.to_h { |row| [row["signer"], row["status"]] }
end

Given('support alerts are captured') do
  @error_reports = []
  allow(ErrorReport).to receive(:notify) { |error, **context| @error_reports << { message: error.message, context: } }
end

Given('Priya and Rahul have signed') do
  ESignature.where(document: @document, position: [1, 2]).update_all(status: "signed")
end

# A completed signature files the signed copy under the document's owner
Given('the agreement belongs to a fund') do
  fund = FactoryBot.create(:fund, entity: @entity)
  @document.update_columns(owner_type: "Fund", owner_id: fund.id)
end

Given('Digio will return the signed copy') do
  signed_pdf = OpenStruct.new(body: File.binread("public/sample_uploads/Offer_1_SPA.pdf"), success?: true, code: 200)
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(signed_pdf)
  digio_audit_trail_answers { digio_audit_trail_pdf }
end

Given('Digio cannot return the signed copy') do
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(OpenStruct.new(body: "Bad gateway", success?: false, code: 502))
end

When('Digio posts a {string} notification with signers:') do |event, table|
  esign_post_notification(digio_callback_signed(esign_statuses_from(table), event:))
end

When('Digio posts a notification without an event with signers:') do |table|
  esign_post_notification(digio_callback_no_event(esign_statuses_from(table)))
end

When('Digio posts a {string} notification for {string} with error code {string}') do |event, email, code|
  raise "only doc.sign.failed is built here" unless event == "doc.sign.failed"

  esign_post_notification(digio_callback_failed(email, code))
end

When('Digio posts a {string} notification for {string}') do |event, email|
  esign_post_notification(digio_callback_rejected(email, event:))
end

When('Digio posts a rejection for {string} that carries no signer list') do |email|
  esign_post_notification(digio_callback_rejected_no_parties(email))
end

When('Digio posts a rejection-shaped notification for {string} without an event') do |email|
  esign_post_notification(digio_callback_rejected(email, event: nil))
end

When('Digio posts a notification for the unknown document {string}') do |document_id|
  esign_post_notification(digio_callback_rejected("priya@lpfund.com", document_id:))
end

When('Digio posts a notification without a document') do
  esign_post_notification({ entities: ["document"], payload: { document: {} }, event: "doc.signed" }.to_json)
end

Then('Digio should have been answered successfully') do
  expect(@esign_response.status).to eq(200), "expected 200, got #{@esign_response.status}: #{@esign_response.body.to_s[0, 200]}"
end

Then('the signer {string} should be {string}') do |email, status|
  expect(ESignature.find_by!(document: @document, email:).reload.status).to eq(status)
end

Then('the agreement should be {string}') do |status|
  expect(@document.reload.esign_status).to eq(status)
end

Then('a signed copy of the agreement should have been created') do
  expect(Document.exists?(entity_id: @entity.id, owner_tag: "Signed")).to be(true)
end

Then('the notification should be recorded in the eSign log') do
  expect(@document.reload.esign_log&.webhook_data).to be_present
end

Then('support should have been alerted about {string}') do |fragment|
  expect(@error_reports.pluck(:message).join("\n")).to include(fragment)
end

Then('support should not have been alerted') do
  expect(@error_reports).to be_empty, "unexpected alerts: #{@error_reports.pluck(:message).inspect}"
end

### Audit trail (esign_audit_trail.feature) #####################################

ESIGN_AUDIT_TRAIL_FILE = "public/sample_uploads/address_proof.pdf".freeze

def digio_audit_trail_pdf
  OpenStruct.new(body: File.binread(ESIGN_AUDIT_TRAIL_FILE), success?: true, code: 200)
end

def digio_audit_trail_refusal
  body = { code: "ACTION_NOT_ALLOWED_IN_CURRENT_STATE", message: "Audit trail is available only on flow completetion" }.to_json
  OpenStruct.new(body:, success?: false, code: 403)
end

# The block gets the attempt number, from 1, and answers as Digio would
def digio_audit_trail_answers
  @audit_trail_requests = 0
  allow_any_instance_of(DigioEsignHelper).to receive(:download_audit_trail) do
    @audit_trail_requests += 1
    yield @audit_trail_requests
  end
end

def esign_audit_trails
  Document.where(from_template_id: @document.id, owner_tag: "Audit Trail")
end

Given('Digio will refuse the audit trail {int} times, then hand it over') do |refusals|
  digio_audit_trail_answers { |attempt| attempt > refusals ? digio_audit_trail_pdf : digio_audit_trail_refusal }
end

Given('Digio will always refuse the audit trail') do
  digio_audit_trail_answers { digio_audit_trail_refusal }
end

When('Digio confirms the last signature') do
  statuses = { "priya@lpfund.com" => "signed", "rahul@orioncap.com" => "signed", "vikram@lawfirm.in" => "signed" }
  esign_post_notification(digio_callback_signed(statuses))
end

Then('the audit trail should be filed beside the signed copy') do
  audit_trail = esign_audit_trails.sole
  signed_copy = Document.find_by!(from_template_id: @document.id, owner_tag: "Signed")
  expect(audit_trail.name).to eq("Subscription Agreement - Audit Trail")
  expect(audit_trail.file.download.read).to eq(File.binread(ESIGN_AUDIT_TRAIL_FILE))
  expect(audit_trail).to have_attributes(owner: signed_copy.owner, folder_id: signed_copy.folder_id, approved: true, locked: true)
  expect(audit_trail.signed?).to be(false)
end

Then('{int} audit trail(s) should be filed') do |count|
  expect(esign_audit_trails.count).to eq(count)
end

Then('Digio should have been asked for the audit trail {int} time(s)') do |count|
  expect(@audit_trail_requests).to eq(count)
end

Then("the signed copy and the audit trail should be in the agreement's folder") do
  folder_id = @document.reload.folder_id
  expect(Document.where(from_template_id: @document.id).pluck(:owner_tag, :folder_id))
    .to contain_exactly(["Signed", folder_id], ["Audit Trail", folder_id])
end

Then('the status check and the notification should be recorded in the eSign log') do
  log = @document.reload.esign_log
  expect(log.manual_update_data).to be_present
  expect(log.webhook_data).to be_present
end

Then("no signer row should hold Digio's responses") do
  expect(ESignature.where(document: @document).pluck(:api_updates).compact_blank).to be_empty
end

### Result handling (embedded_esign_result.feature) #############################

# Stands in for the HTTParty response of Digio's document status call
DigioStatusResponse = Struct.new(:body) do
  def success?
    true
  end

  def [](key)
    JSON.parse(body)[key]
  end
end

Given('Digio status checks are recorded') do
  @status_checks = []
  allow(DocumentEsignUpdateJob).to receive(:perform_later) do |document_id, user_id|
    @status_checks << { document_id:, user_id: }
  end
end

Given("Digio's status shows:") do |table|
  statuses = esign_statuses_from(table)
  body = { id: ESIGN_DIGIO_DOC_ID, agreement_status: "requested", signing_parties: digio_signing_parties(statuses) }.to_json
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(DigioStatusResponse.new(body))
end

When('the status check runs for the agreement') do
  DocumentEsignUpdateJob.perform_now(@document.id, nil)
end

# Drives the callbacks the page registered with the (stubbed) SDK
When('the Digio panel reports the event {string}') do |name|
  event = { event: name, txnId: "TXN-1", documentId: ESIGN_DIGIO_DOC_ID, entity: "sign" }
  page.execute_script("window.__digioOptions.event_listener(#{event.to_json})")
end

When('the Digio panel calls back with the error code {string}') do |code|
  response = { error_code: code, message: "Signing failed", digio_doc_id: ESIGN_DIGIO_DOC_ID }
  page.execute_script("window.__digioOptions.callback(#{response.to_json})")
end

When('the Digio panel calls back with a success') do
  response = { txn_id: "TXN-1", digio_doc_id: ESIGN_DIGIO_DOC_ID }
  page.execute_script("window.__digioOptions.callback(#{response.to_json})")
end

# What the sandbox sends when the panel is closed with X (seen in the Digio sandbox spike)
When('the Digio panel is closed by the signer') do
  response = { digio_doc_id: ESIGN_DIGIO_DOC_ID, error_code: "CANCELLED", message: "Signing Cancelled", last_state: nil }
  page.execute_script("window.__digioOptions.callback(#{response.to_json})")
end

def esign_post_result(poster_email, signature, code)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: poster_email, password: "password" } }
  session.post sign_result_e_signature_path(signature), params: { event: "sign.failed", error_code: code }.to_json,
                                                        headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  @result_response = session.response
end

When('{string} reports the code {string} from the signing page') do |email, code|
  esign_post_result(email, ESignature.find_by!(document: @document, email:), code)
end

When('{string} reports the code {string} for the signature of {string}') do |poster, code, signer|
  esign_post_result(poster, ESignature.find_by!(document: @document, email: signer), code)
end

Then('the signing result message should be {string} with the next step {string}') do |message, action|
  expect(@result_response.status).to eq(200), "expected 200, got #{@result_response.status}: #{@result_response.body.to_s[0, 200]}"
  body = JSON.parse(@result_response.body)
  expect(body).to eq("message" => message, "action" => action)
end

Then('the signing result should be refused with {string}') do |message|
  expect(@result_response.status).to eq(403)
  expect(JSON.parse(@result_response.body)["message"]).to eq(message)
end

def esign_wait_for_status_check(wait: 10)
  deadline = Time.zone.now + wait
  sleep 0.1 while @status_checks.empty? && Time.zone.now < deadline
end

Then('a Digio status check should have been requested for the agreement') do
  esign_wait_for_status_check
  expect(@status_checks.pluck(:document_id)).to include(@document.id)
end

Then('a Digio status check should not have been requested for the agreement') do
  expect(@status_checks).to be_empty, "unexpected status checks: #{@status_checks.inspect}"
end

Then('no Digio status check should have been requested') do
  expect(@status_checks).to be_empty, "unexpected status checks: #{@status_checks.inspect}"
end

Then('support should have been alerted') do
  expect(@error_reports).not_to be_empty, "expected an alert, none was raised"
end

Then('no signed copy of the agreement should exist') do
  expect(Document.exists?(entity_id: @entity.id, owner_tag: "Signed")).to be(false)
end

def esign_sdk_events
  (@document.reload.esign_log&.sdk_events || {}).values
end

Then('the eSign log should record {string} for {string}') do |event, email|
  match = esign_sdk_events.find { |e| e["event"] == event && e["signer_email"] == email }
  expect(match).to be_present, "no #{event} entry for #{email}: #{esign_sdk_events.inspect}"
  expect(match["at"]).to be_present
end

Then('the eSign log should record the code {string} for {string}') do |code, email|
  match = esign_sdk_events.find { |e| e["error_code"] == code && e["signer_email"] == email }
  expect(match).to be_present, "no #{code} entry for #{email}: #{esign_sdk_events.inspect}"
end

Then('the eSign log should have no recorded events') do
  expect(esign_sdk_events).to be_empty
end

### Signer notifications (embedded_esign_notifications.feature) ##################

# An investor signs another entity's document, so the platform's email gate looks for an investor access
def esign_grant_investor_access(user, email_enabled:)
  investor = FactoryBot.create(:investor, entity: @entity, investor_entity: user.entity)
  @esign_investor_access = InvestorAccess.create!(entity: @entity, investor:, user:, email: user.email, first_name: user.first_name,
                                                  last_name: user.last_name, approved: true, email_enabled:)
end

Given('Orion Capital has approved the {string} for Priya, Rahul and Vikram but not yet sent it') do |document_name|
  step %(Orion Capital has sent the "#{document_name}" for eSignature to Priya, Rahul and Vikram)
  @document.update_columns(sent_for_esign: false, sent_for_esign_date: nil, esign_status: "", provider_doc_id: nil, signature_enabled: true)
  ESignature.where(document: @document).update_all(status: "")
  esign_grant_investor_access(@priya, email_enabled: true)
  ActionMailer::Base.deliveries.clear
end

Given('Digio accepts the document') do
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api)
    .and_return(DigioStatusResponse.new({ id: ESIGN_DIGIO_DOC_ID }.to_json))
end

Given("Priya's investor access has email turned off") do
  @esign_investor_access.update_columns(email_enabled: false)
end

Given('the notifier raises when it is used') do
  allow(EsignSigningNotifier).to receive(:with).and_raise(StandardError, "notifier down")
end

When('Meera sends the agreement for eSignature') do
  DigioEsignHelper.new.sign(@document.reload, @meera.id)
end

Given('Meera has sent the agreement for eSignature') do
  DigioEsignHelper.new.sign(@document.reload, @meera.id)
end

Given('Priya has signed and the status was confirmed') do
  ESignature.find_by!(document: @document, email: "priya@lpfund.com").update_columns(status: "signed")
end

When('Meera re-sends the agreement for eSignature') do
  result = ResendDocumentForEsign.call(document: @document.reload, user_id: @meera.id)
  expect(result.success?).to be(true), "re-send failed: #{result[:errors]}"
end

def esign_signing_notifications_for(email)
  user = User.find_by!(email:)
  Noticed::Notification.where(recipient: user).select { |n| n.event.type == "EsignSigningNotifier" }
end

def esign_signing_emails
  ActionMailer::Base.deliveries.select { |m| m.subject.to_s.start_with?("Your signature is requested:") }
end

Then('{string} should have the bell entry {string}') do |email, message|
  notifications = esign_signing_notifications_for(email)
  expect(notifications.map(&:message)).to include(message)
end

Then('{string} should have no signing notifications') do |email|
  user = User.find_by(email:)
  expect(user.nil? || esign_signing_notifications_for(email).empty?).to be(true),
                                                                        "unexpected notifications for #{email}"
end

Then('{string} should have {int} signing notification(s)') do |email, count|
  expect(esign_signing_notifications_for(email).size).to eq(count)
end

Then('{string} should have received the email {string}') do |email, subject|
  mail = esign_signing_emails.find { |m| Array(m.to).include?(email) }
  expect(mail).to be_present, "no signing email to #{email}; sent: #{esign_signing_emails.map { |m| [m.to, m.subject] }.inspect}"
  expect(mail.subject).to eq(subject)
end

Then('{string} should have received {int} signing email(s)') do |email, count|
  expect(esign_signing_emails.count { |m| Array(m.to).include?(email) }).to eq(count)
end

Then('no signing email should have been sent') do
  expect(esign_signing_emails).to be_empty
end

# BaseNotifier only applies the email_enabled gate outside the test environment, so a scenario cannot see a
# withheld email in ActionMailer; it asserts the very predicate production uses (NotificationExtensions#email_enabled).
Then('the email gate for {string} should be open') do |email|
  expect(esign_signing_notifications_for(email).first.email_enabled).to be_truthy
end

Then('the email gate for {string} should be closed') do |email|
  expect(esign_signing_notifications_for(email).first.email_enabled).to be_falsey
end

Then('the signer {string} should be marked as notified') do |email|
  expect(ESignature.find_by!(document: @document, email:).signing_notified_at).to be_present
end

When('{string} opens the bell entry') do |email|
  notification = esign_signing_notifications_for(email).last
  @esign_bell_entry = notification
  esign_login_as(email)
  visit notification_path(notification)
end

Then('I should be on the signing page of {string}') do |email|
  signature = ESignature.find_by!(document: @document, email:)
  expect(page).to have_current_path(sign_e_signature_path(signature))
end

Then('the bell entry of {string} should be read') do |_email|
  expect(@esign_bell_entry.reload.read_at).to be_present
end

Then('the email to {string} should link to the signing page and say Digio\'s link also works') do |email|
  signature = ESignature.find_by!(document: @document, email:)
  mail = esign_signing_emails.find { |m| Array(m.to).include?(email) }
  body = mail.body.to_s
  expect(body).to include("/e_signatures/#{signature.id}/sign")
  expect(body).to include("Orion Capital")
  expect(body).to include("Digio has also sent you a signing link. Either one works.")
end
