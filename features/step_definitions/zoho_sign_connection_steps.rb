# The Zoho eSign panel on the company page. Zoho is the WebMock fake in
# features/support/zoho_sign_stub.rb (`zoho_fake`), so scenarios are tagged @zoho-http.

Given('the company has connected its Zoho account in {string}') do |region|
  zoho_fake
  @connection = FactoryBot.create(:zoho_sign_connection, entity: @entity, region:)
end

Given('the company\'s Zoho account needs reconnecting') do
  @connection.update!(status: :needs_reauth, last_error: "Zoho rejected the access token")
end

Given('the company\'s webhook secret has been shown') do
  @connection.update!(webhook_secret_revealed_at: 1.minute.ago)
end

Given('{int} documents are out for signature on the company\'s Zoho account') do |count|
  steps %(Given there is an existing investor "entity_type=Family Office")
  count.times do |idx|
    Document.create!(entity: @entity, user: @user, owner: @investor, folder: @investor.document_folder, name: "Out for signature #{idx + 1}",
                     approved: true, file: Rails.public_path.join("sample_uploads/rta_demo_fund_11_success.pdf").open,
                     sent_for_esign: true, sent_for_esign_date: Time.current, esign_status: "inprogress", provider_doc_id: "zoho-#{idx}")
  end
end

Given('{string} is a company admin of the company without the support role') do |first_name|
  @other_user = FactoryBot.create(:user, entity: @entity, first_name:)
  @other_user.add_role(:company_admin)
end

Given('{string} is a company admin of another company') do |first_name|
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
  @other_user = FactoryBot.create(:user, entity: other_entity, first_name:)
  @other_user.add_role(:company_admin)
end

Given('{string} is logged in') do |_first_name|
  Capybara.reset_sessions!
  log_in(@other_user)
end

When('the admin opens the company page') do
  zoho_fake
  visit(entity_path(@entity))
end

When('the admin connects Zoho with region {string} and grant code {string}') do |region_name, grant_code|
  steps %(When the admin opens the company page)
  within("#zoho_sign_connection_panel") do
    select(region_name, from: "zoho_sign_connection_region") if region_name.present?
    fill_in("zoho_sign_connection_client_id", with: "1000.ARKACLIENT")
    fill_in("zoho_sign_connection_client_secret", with: "arka-client-secret")
    fill_in("zoho_sign_connection_grant_code", with: grant_code)
    click_on("Connect")
  end
end

When('the admin connects Zoho leaving the client secret and grant code blank') do
  steps %(When the admin opens the company page)
  within("#zoho_sign_connection_panel") do
    select("United States (sign.zoho.com)", from: "zoho_sign_connection_region")
    fill_in("zoho_sign_connection_client_id", with: "1000.ARKACLIENT")
    click_on("Connect")
  end
end

When('the admin reconnects Zoho with grant code {string} leaving the client secret blank') do |grant_code|
  steps %(When the admin opens the company page)
  @connected_at_before = @connection.reload.connected_at
  within("#zoho_sign_connection_panel") do
    find("summary", text: "Reconnect").click
    fill_in("zoho_sign_connection_grant_code", with: grant_code)
    click_on("Reconnect")
  end
end

When('the admin clicks {string} on the Zoho eSign panel') do |button|
  steps %(When the admin opens the company page) unless page.has_css?("#zoho_sign_connection_panel", wait: 0)
  within("#zoho_sign_connection_panel") { click_on(button) }
end

When('the admin disconnects the Zoho account and confirms') do
  steps %(When the admin opens the company page)
  accept_confirm { within("#zoho_sign_connection_panel") { click_on("Disconnect") } }
end

When('the admin regenerates the webhook secret and confirms') do
  steps %(When the admin opens the company page)
  accept_confirm { within("#zoho_sign_connection_panel") { click_on("Regenerate webhook secret") } }
  # the new secret is saved once the panel says so
  within("#zoho_sign_connection_panel") { expect(page).to have_content("New webhook secret created") }
end

# E5: two Connect requests for the same company landing together - the unique index decides.
When('two connect requests for the company arrive together') do
  zoho_fake
  params = ActionController::Parameters.new(region: "com", client_id: "1000.ARKACLIENT", client_secret: "arka-client-secret", grant_code: "code-1")
  @results = Array.new(2) { ZohoSignConnectionSetup.new.connect(@entity, params, @user) }
end

# A request the page doesn't offer (another region, another company's URL), sent from the browser
# the way a tampered page would.
When('a direct {string} request with region {string} is sent to the company\'s Zoho connection') do |verb, region|
  zoho_fake
  visit(root_path)
  path = entity_zoho_sign_connection_path(@entity)
  body = { "zoho_sign_connection[region]" => region, "zoho_sign_connection[client_id]" => "1000.ARKACLIENT",
           "zoho_sign_connection[client_secret]" => "arka-client-secret", "zoho_sign_connection[grant_code]" => "code-1" }
  @request_status = page.evaluate_script(<<~JS)
    (() => {
      const body = new URLSearchParams(#{body.to_json});
      return fetch(#{path.to_json}, { method: #{verb.upcase.to_json}, redirect: "manual", body,
        headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" } })
        .then(r => r.status);
    })()
  JS
end

Then('the Zoho eSign panel shows {string}') do |text|
  within("#zoho_sign_connection_panel") { expect(page).to have_content(text) }
end

Then('there is no Zoho eSign panel') do
  expect(page).to have_no_css("#zoho_sign_connection_panel")
  expect(page).to have_no_content("Zoho eSign")
end

Then('the panel shows the connection time') do
  connected_at = ZohoSignConnection.find_by!(entity_id: @entity.id).connected_at
  within("#zoho_sign_connection_panel") { expect(page).to have_content(I18n.l(connected_at)) }
end

Then('the company is connected to Zoho in {string}') do |region|
  connection = ZohoSignConnection.find_by!(entity_id: @entity.id)
  expect(connection.region).to eq(region)
  expect(connection).to be_connected
  expect(connection.refresh_token).to start_with("zoho-refresh-")
end

Then('the company has no Zoho connection') do
  expect(ZohoSignConnection.where(entity_id: @entity.id)).not_to exist
end

Then('the company has exactly one Zoho connection') do
  expect(ZohoSignConnection.where(entity_id: @entity.id).count).to eq(1)
end

Then('the second connect request is told {string}') do |message|
  expect(@results.first).to be_success
  expect(@results.last).not_to be_success
  expect(@results.last.message).to eq(message)
end

Then('the grant code was exchanged at {string}') do |host|
  expect(zoho_fake.calls_to(:token).map(&:host)).to include(host)
end

Then('the grant code was exchanged with the stored client secret') do
  expect(zoho_fake.calls_to(:token).last.query["client_secret"]).to eq("arka-client-secret")
end

Then('nothing was sent to Zoho\'s accounts server') do
  expect(zoho_fake.calls_to(:token)).to be_empty
end

Then('the company\'s Zoho connection is {string}') do |status|
  expect(@connection.reload.status).to eq(status)
end

Then('the company\'s Zoho connection still has its original credentials') do
  @connection.reload
  expect(@connection.refresh_token).to eq("arka-refresh-token")
  expect(@connection.client_secret).to eq("arka-client-secret")
end

Then('the company\'s Zoho connection keeps its original connected on time') do
  expect(@connection.reload.connected_at.to_i).to eq(@connected_at_before.to_i)
end

Then('the webhook secret is shown') do
  within("#zoho_sign_connection_panel") { expect(page).to have_css("#zoho_sign_webhook_secret", text: @connection.reload.webhook_secret) }
end

Then('the panel offers only to regenerate the webhook secret') do
  visit(entity_path(@entity))
  within("#zoho_sign_connection_panel") do
    expect(page).to have_no_button("Show webhook secret")
    expect(page).to have_button("Regenerate webhook secret")
    expect(page).to have_no_content(@connection.reload.webhook_secret)
  end
end

Then('the request is refused') do
  expect(@request_status).not_to eq(200)
end

Then('the client secret and grant code are filtered from the request log') do
  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  filtered = filter.filter("zoho_sign_connection" => { "client_secret" => "arka-client-secret", "grant_code" => "code-1", "client_id" => "1000.ARKACLIENT" })
  expect(filtered["zoho_sign_connection"]).to include("client_secret" => "[FILTERED]", "grant_code" => "[FILTERED]", "client_id" => "1000.ARKACLIENT")
end

Then('the company admins are emailed once that the Zoho account needs reconnecting') do
  mails = ActionMailer::Base.deliveries.select { |mail| mail.subject.to_s.include?("reconnect") }
  expect(mails.size).to eq(@entity.employees.active.company_admins.count)
  expect(mails.flat_map(&:cc).uniq).to eq([ENV.fetch("SUPPORT_EMAIL_TO")])
  expect((mails.first.html_part || mails.first).decoded).to include("contact CapHive support")
end

Given('the company had connected its Zoho account in {string} before the document was sent') do |region|
  @connection = FactoryBot.create(:zoho_sign_connection, entity: @entity, region:, connected_at: @doc.reload.sent_for_esign_date - 1.minute)
end

Given('the document was sent exactly when the company connected') do
  @connection.update!(connected_at: @doc.reload.sent_for_esign_date)
end

Given('the document was sent {int} second(s) before the company connected') do |seconds|
  @connection.update!(connected_at: @doc.reload.sent_for_esign_date + seconds.seconds)
end

Given('another company {string} has its own Zoho connection with webhook secret {string}') do |name, secret|
  other_entity = FactoryBot.create(:entity, entity_type: "Investment Fund", name:)
  @other_connection = FactoryBot.create(:zoho_sign_connection, entity: other_entity, region: "jp", webhook_secret: secret)
end

Given('Zoho access tokens are cached') do
  cache = ActiveSupport::Cache::MemoryStore.new
  allow(Rails).to receive(:cache).and_return(cache)
end

Given('Zoho\'s call log is cleared') do
  zoho_fake.calls.clear
end

When('the company reconnects with new credentials') do
  @connection.update!(client_secret: "arka-client-secret-2", refresh_token: "arka-refresh-token-2")
end

When('Zoho posts {string} for {string} to the company\'s webhook address signed with {string}') do |operation_type, email, secret|
  payload = { notifications: { operation_type:, performed_by_email: email }, requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post(zoho_sign_webhook_path(@connection.webhook_token), payload, secret == "nothing" ? nil : secret)
end

When('Zoho posts {string} by {string} for the signer slot of {string} to the company\'s webhook address signed with {string}') do |operation_type, by_email, slot_email, secret|
  action_id = @doc.e_signatures.find_by!(email: slot_email).provider_signer_id
  payload = { notifications: { operation_type:, performed_by_email: by_email, action_id: }, requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post(zoho_sign_webhook_path(@connection.webhook_token), payload, secret)
end

When('Zoho posts {string} for request {string} to the company\'s webhook address signed with {string}') do |operation_type, request_id, secret|
  payload = { notifications: { operation_type:, performed_by_email: "rohan@example.com" }, requests: { request_id: } }
  zoho_signed_post(zoho_sign_webhook_path(@connection.webhook_token), payload, secret)
end

When('Zoho posts {string} for the company\'s request to {string}\'s webhook address signed with {string}') do |operation_type, _name, secret|
  payload = { notifications: { operation_type:, performed_by_email: "rohan@example.com" }, requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post(zoho_sign_webhook_path(@other_connection.webhook_token), payload, secret)
end

When('Zoho posts {string} to the webhook address {string}') do |operation_type, token|
  payload = { notifications: { operation_type: }, requests: { request_id: @doc.reload.provider_doc_id } }
  zoho_signed_post(zoho_sign_webhook_path(token), payload, "arka-secret")
end

Then('the company\'s webhook shows a last update') do
  expect(@connection.reload.last_webhook_at).to be_present
end

Then('the documents out for signature keep their status {string}') do |status|
  expect(Document.where(entity_id: @entity.id, sent_for_esign: true).where.not(id: @doc&.id).pluck(:esign_status).uniq).to eq([status])
end

Then('Zoho issued access tokens for refresh tokens {string}') do |tokens|
  used = zoho_fake.calls_to(:token).filter_map { |call| call.query["refresh_token"] }
  expect(used).to eq(tokens.split(",").map(&:strip))
end
