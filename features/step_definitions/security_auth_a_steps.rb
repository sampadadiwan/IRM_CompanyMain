# frozen_string_literal: true

# Steps for the 2026-10 security review, "Authentication and session — Medium / Low":
#   M1 (webhook authentication), M2 + N5 (OAuth clients), M6 (token endpoints), L2 Phase 1
#   (hashed Doorkeeper tokens) and L9 (webhook replay).
# Design and worked examples: docs/security/security_review_2026_10.md.
#
# Every request here is an in-process ActionDispatch::Integration::Session (or the Rack::Test
# RackAttackClient for the throttles), so RSpec stubs on credentials, ENV and job classes apply to
# the request, and no browser or app server is involved.
#
# Reused from elsewhere: "there is a user ... for an entity ..." (features/common.rb), the MCP client
# steps (mcp_transport_steps.rb), the mail API steps (outlook_steps.rb), the users_sync steps
# (sync_steps.rb), the Zoho document steps (zoho_esign_steps.rb) and the Rack::Attack visitors
# (rack_attack_404_steps.rb).

# ── Helpers ─────────────────────────────────────────────────────────────────

module SecurityAuthAHelpers
  # The callback Claude.ai registers (docs/modules/ai/mcp_server/technical_design.md)
  CLAUDE_CALLBACK = "https://claude.ai/api/mcp/auth_callback"

  # A fresh, cookie-less client: a webhook sender or an OAuth client's back end
  def sa_client
    ActionDispatch::Integration::Session.new(Rails.application)
  end

  # The user's browser, signed in through the real Devise endpoint
  def sa_browser
    @sa_browser ||= sa_client.tap do |session|
      session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
      expect(session.response.status).to eq(302), "sign-in failed: HTTP #{session.response.status}"
    end
  end

  # Stubs one credentials key for the scenario; every other lookup still reads the real file
  def sa_stub_credential(*path, value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(*path).and_return(value)
  end

  # ── M2 / L2: the OAuth authorization-code flow an MCP client runs ──

  # RFC 7591 registration, as Claude.ai and ChatGPT send it (public client, PKCE)
  def sa_register(client_name, redirect_uris)
    @sa_registration = sa_client.tap do |session|
      session.post "/oauth/registration",
                   params: { client_name:, redirect_uris:, token_endpoint_auth_method: "none",
                             grant_types: ["authorization_code"], response_types: ["code"] }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    end.response
  end

  def sa_registration_json
    JSON.parse(@sa_registration.body)
  end

  def sa_authorize_params
    @sa_verifier ||= SecureRandom.urlsafe_base64(48)
    { client_id: @sa_client_id, redirect_uri: @sa_redirect_uri, response_type: "code", scope: "read", state: "sa-state",
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(@sa_verifier), padding: false),
      code_challenge_method: "S256" }
  end

  # Consent page, then the Authorize button, then the code exchange; returns the token response
  def sa_authorize_and_exchange
    sa_browser.get "/oauth/authorize", params: sa_authorize_params
    expect(sa_browser.response.status).to eq(200), "consent page: HTTP #{sa_browser.response.status} #{sa_browser.response.body.first(300)}"
    sa_browser.post "/oauth/authorize", params: sa_authorize_params
    expect(sa_browser.response.status).to eq(302), "authorize: HTTP #{sa_browser.response.status}"
    code = Rack::Utils.parse_query(URI.parse(sa_browser.response.location).query)["code"]
    expect(code).to be_present, "no code in #{sa_browser.response.location}"

    token_client = sa_client
    token_client.post "/oauth/token", params: { grant_type: "authorization_code", code:, redirect_uri: @sa_redirect_uri,
                                                client_id: @sa_client_id, code_verifier: @sa_verifier }
    expect(token_client.response.status).to eq(200), "token: HTTP #{token_client.response.status} #{token_client.response.body}"
    JSON.parse(token_client.response.body)
  end

  # ── M6: devise-api's token endpoints ──

  def sa_token_request(path, params)
    @sa_token_response = sa_client.tap do |session|
      session.post path, params: params.to_json, headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
    end.response
  end

  # ── M1: webhook senders ──

  def sa_webhook_post(path, body, query: nil, headers: {})
    target = query.nil? ? path : "#{path}?#{query.to_query}"
    @sa_webhook_response = sa_client.tap do |session|
      session.post target, params: body, headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }.merge(headers)
    end.response
  end

  # A Digio "signed" notification (shape of embedded_esign_steps.rb's digio callbacks)
  def sa_digio_body
    { entities: ["document"], event: "doc.signed",
      payload: { document: { id: "DID-WEBHOOK-AUTH", signing_parties: [{ identifier: "priya@lpfund.com", status: "signed" }] } } }.to_json
  end

  # A DocuSign Connect envelope-completed notification
  def sa_docusign_body
    { event: "envelope-completed", data: { accountId: "acc-1", envelopeId: "env-1", envelopeSummary: { status: "completed" } } }.to_json
  end

  def sa_docusign_hmac(key, body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, body))
  end

  # ── L9: Zoho events ──

  def sa_zoho_body(operation_type, email, minutes_ago)
    { notifications: { operation_type:, performed_by_email: email, performed_at: (Time.current - minutes_ago.minutes).to_i * 1000 },
      requests: { request_id: @doc.reload.provider_doc_id } }.to_json
  end
end
World(SecurityAuthAHelpers)

# ── M1 — webhook tokens ─────────────────────────────────────────────────────

Given("this environment's WhatsApp webhook token is {string}") do |token|
  sa_stub_credential(:whatsapp, :webhook_token, token)
end

Given("this environment's eSign webhook token is {string}") do |token|
  sa_stub_credential(:esign, :webhook_token, token)
end

Given("this environment's DocuSign Connect HMAC key is {string}") do |key|
  sa_stub_credential(:esign, :docusign_connect_key, key)
end

Given("webhook token enforcement is on") do
  allow(ENV).to receive(:[]).and_call_original
  allow(ENV).to receive(:[]).with(WebhookToken::ENFORCE_ENV).and_return("1")
end

# M1-E — the state production deploys in: enforcement unset
Given("webhook token enforcement is off") do
  allow(ENV).to receive(:[]).and_call_original
  allow(ENV).to receive(:[]).with(WebhookToken::ENFORCE_ENV).and_return(nil)
end

# Spies on what a webhook would trigger, so a scenario sees whether a post was applied without
# running the WhatsApp agent or a provider's API
Given("webhook side effects are recorded") do
  allow(WhatsappAgentJob).to receive(:perform_later)
  allow(EsignHelper).to receive(:update_signature_progress)
  allow(Rails.logger).to receive(:warn).and_call_original
end

When("WATI posts an inbound message with the webhook token {string}") do |token|
  query = token.empty? ? nil : { webhook_token: token }
  sa_webhook_post("/users/whatsapp_webhook", { eventType: "message", owner: false, waId: "919800000001", text: "hi" }.to_json, query:)
end

When("Digio posts a signed notification with the webhook token {string}") do |token|
  query = token.empty? ? nil : { webhook_token: token }
  sa_webhook_post("/documents/signature_progress", sa_digio_body, query:)
end

When("DocuSign posts a completed envelope with the webhook token {string}") do |token|
  query = token.empty? ? nil : { webhook_token: token }
  sa_webhook_post("/documents/signature_progress", sa_docusign_body, query:)
end

When("DocuSign posts a completed envelope signed with the key {string} and the webhook token {string}") do |key, token|
  query = token.empty? ? nil : { webhook_token: token }
  sa_webhook_post("/documents/signature_progress", sa_docusign_body, query:,
                                                                     headers: { "X-DocuSign-Signature-1" => sa_docusign_hmac(key, sa_docusign_body) })
end

Then("the webhook should be answered with {int}") do |status|
  expect(@sa_webhook_response.status).to eq(status), "got #{@sa_webhook_response.status}: #{@sa_webhook_response.body.first(200)}"
end

Then("the WhatsApp message should have been handed to the agent without the webhook token") do
  expect(WhatsappAgentJob).to have_received(:perform_later).once
  # The secret never reaches Sidekiq's queue
  expect(WhatsappAgentJob).to have_received(:perform_later).with(satisfy { |json| !JSON.parse(json).key?("webhook_token") })
end

Then("the WhatsApp message should not have been handed to the agent") do
  expect(WhatsappAgentJob).not_to have_received(:perform_later)
end

Then("the eSign update should have been applied without the webhook token") do
  expect(EsignHelper).to have_received(:update_signature_progress).once
  # Nor the eSign log, which records what the helper is given
  expect(EsignHelper).to have_received(:update_signature_progress).with(satisfy { |params| !params.to_unsafe_h.key?("webhook_token") })
end

Then("the eSign update should not have been applied") do
  expect(EsignHelper).not_to have_received(:update_signature_progress)
end

Then("a warning should be logged that the {string} was accepted without authentication") do |source|
  expect(Rails.logger).to have_received(:warn).with(/\[WebhookToken\] #{Regexp.escape(source)} accepted without authentication/).at_least(:once)
end

# ── L9 — users_sync replay and ordering ─────────────────────────────────────

# Signs once and sends the identical request twice: what someone replaying a captured request does
When("I POST the same signed request to {string} twice") do |path|
  body = JSON.generate(@payload)
  ts   = Time.now.utc.iso8601(3)
  sig  = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.credentials.CROSS_INSTANCE_SECRET,
                                 "POST\n#{path}\n#{ts}\n#{Digest::SHA256.hexdigest(body)}")
  headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json",
              "X-Timestamp" => ts, "X-Region" => @payload[:origin_region].to_s, "X-Signature" => sig }
  @sa_sync_responses = Array.new(2) { sa_client.tap { |session| session.post(path, params: body, headers:) }.response }
  # The shared sync assertions read @last_response
  @last_response = @sa_sync_responses.last
end

Then("the first copy should have been applied") do
  expect(@sa_sync_responses.first.status).to eq(200), @sa_sync_responses.first.body
  expect(JSON.parse(@sa_sync_responses.first.body)["applied"]).to be(true)
end

# L9-2 — an UPSERT the origin built before the one already applied (slow, or replayed later)
Given("the payload was built {int} minute(s) before the last update applied to {string}") do |minutes, email|
  last_applied = User.find_by!(email:).last_synced_at
  expect(last_applied).to be_present
  @payload[:as_of] = (last_applied - minutes.minutes).utc.iso8601(3)
end

Given("the payload was built just now") do
  @payload[:as_of] = Time.now.utc.iso8601(3)
end

# ── L9 — Zoho replay and ordering ───────────────────────────────────────────

Given("Zoho webhook deliveries are counted") do
  allow(ZohoWebhookJob).to receive(:perform_later).and_call_original
end

# Unsigned: the test environment has no platform Zoho secret, which is accepted locally (E34)
When("Zoho posts {string} for {string} performed {int} minute(s) ago") do |operation_type, email, minutes|
  @sa_zoho_body = sa_zoho_body(operation_type, email, minutes)
  sa_webhook_post("/documents/signature_progress", @sa_zoho_body)
end

When("Zoho posts the same body again") do
  sa_webhook_post("/documents/signature_progress", @sa_zoho_body)
end

Then("the Zoho update should have been queued {int} time(s)") do |count|
  expect(ZohoWebhookJob).to have_received(:perform_later).exactly(count).times
end

# ── M2 / N5 — OAuth clients ─────────────────────────────────────────────────

When("Claude.ai registers itself as {string}") do |name|
  sa_register(name, [SecurityAuthAHelpers::CLAUDE_CALLBACK])
end

When("a client registers itself as {string} with the redirect URIs {string}") do |name, uris|
  sa_register(name, uris.split(","))
end

Then("the registration should succeed") do
  expect(@sa_registration.status).to eq(201), "got #{@sa_registration.status}: #{@sa_registration.body}"
  @sa_client_id = sa_registration_json["client_id"]
  @sa_redirect_uri = sa_registration_json["redirect_uris"].first
end

Then("the registration should be refused with {string}") do |error|
  expect(@sa_registration.status).to eq(400), "got #{@sa_registration.status}: #{@sa_registration.body}"
  expect(sa_registration_json["error"]).to eq(error)
end

Then("no OAuth application named {string} should exist") do |name|
  expect(Doorkeeper::Application.where(name:).count).to eq(0)
end

Then("the registered client should be of the kind {string}") do |kind|
  expect(McpClientRegistry.kind_for(Doorkeeper::Application.find_by!(uid: @sa_client_id))).to eq(kind)
end

When("the user opens the consent page for that client") do
  sa_browser.get "/oauth/authorize", params: sa_authorize_params
end

Then("the consent page should say the user will be sent back to {string}") do |host|
  expect(sa_browser.response.status).to eq(200)
  expect(Nokogiri::HTML(sa_browser.response.body).at_css("#oauth-redirect-host").text.squish)
    .to include("you will be sent back to #{host}")
end

When("the user authorizes that client") do
  @sa_token_json = sa_authorize_and_exchange
  # The MCP client steps present @mcp_token
  @mcp_token = @sa_token_json["access_token"]
end

Given("the entity allows only the AI client {string}") do |entry|
  @entity.entity_setting.update!(mcp_allowed_clients_list: [entry])
end

# An app that exists from before registration was gated — anyone could have made it
Given("an OAuth app {string} was registered earlier with the callback {string}") do |name, callback|
  @sa_app = Doorkeeper::Application.create!(name:, redirect_uri: callback, scopes: "read", confidential: false)
end

Given("the user has an MCP access token for that app") do
  @mcp_token = Doorkeeper::AccessToken.create!(application: @sa_app, resource_owner_id: @user.id, entity_id: @entity.id,
                                               scopes: "read", expires_in: 1.hour.to_i).plaintext_token
end

# N5 — what a self-registered impostor's token would be
Given("the user has a token for that app as their mail token") do
  @mail_token = Doorkeeper::AccessToken.create!(application: @sa_app, resource_owner_id: @user.id, entity_id: @entity.id,
                                                scopes: "read", expires_in: 1.hour.to_i).plaintext_token
end

Then("that token should not count as a mail add-in token") do
  expect(MailAddinToken.issued?(Doorkeeper::AccessToken.by_token(@mail_token))).to be(false)
end

Then("the mail add-in tokens should still be issued by the server-created app") do
  token = MailAddinToken.issue_for(@user)
  expect(token.application).not_to eq(@sa_app)
  expect(token.application.redirect_uri).to eq("urn:ietf:wg:oauth:2.0:oob")
  expect(MailAddinToken.issued?(token)).to be(true)
end

# M2-X — introspection of ANOTHER live token of the same client, asked both ways Doorkeeper accepts:
# with a bearer token of that client, and with the client's own credentials. Under the old
# `allow_token_introspection { true }` both answered {"active": true, ...}. (A token asking about
# itself is refused by Doorkeeper whatever the setting, so it would prove nothing.)
When("the client introspects another of the user's tokens") do
  app = Doorkeeper::Application.create!(name: "Introspecting client", redirect_uri: SecurityAuthAHelpers::CLAUDE_CALLBACK,
                                        scopes: "read", confidential: true)
  bearer, other = Array.new(2) do
    Doorkeeper::AccessToken.create!(application: app, resource_owner_id: @user.id, entity_id: @entity.id,
                                    scopes: "read", expires_in: 1.hour.to_i).plaintext_token
  end
  @sa_introspections = [
    sa_client.tap { |session| session.post "/oauth/introspect", params: { token: other }, headers: { "Authorization" => "Bearer #{bearer}" } }.response,
    sa_client.tap do |session|
      session.post "/oauth/introspect", params: { token: other },
                                        headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(app.uid, app.plaintext_secret) }
    end.response
  ]
end

Then("neither introspection should report the token") do
  bearer_answer, client_answer = @sa_introspections
  # Bearer: refused outright
  expect(bearer_answer.status).to eq(401), "bearer: #{bearer_answer.status} #{bearer_answer.body}"
  # Client credentials: RFC 7662 answers "inactive", with nothing else about the token
  expect(JSON.parse(client_answer.body)).to eq("active" => false)
end

# ── L2 — hashed tokens ──────────────────────────────────────────────────────

Then("the access token should be stored hashed, not as issued") do
  row = Doorkeeper::AccessToken.find_by!(token: Digest::SHA256.hexdigest(@mcp_token))
  expect(row.token).not_to eq(@mcp_token)
  expect(Doorkeeper::AccessToken.where(token: @mcp_token)).to be_none
  # The refresh token likewise
  expect(row.refresh_token).not_to eq(@sa_token_json["refresh_token"]) if @sa_token_json&.dig("refresh_token")
end

Then("the mail token should be stored hashed, not as issued") do
  expect(Doorkeeper::AccessToken.where(token: @mail_token)).to be_none
  expect(Doorkeeper::AccessToken.where(token: Digest::SHA256.hexdigest(@mail_token))).to exist
end

# L2-1 — a row written before hashing was switched on still holds the raw value
Given("the user's MCP access token was stored in plaintext before the upgrade") do
  row = Doorkeeper::AccessToken.find_by!(token: Digest::SHA256.hexdigest(@mcp_token))
  row.update_column(:token, @mcp_token)
end

Then("the access token row should now be stored hashed") do
  expect(Doorkeeper::AccessToken.where(token: @mcp_token)).to be_none
  expect(Doorkeeper::AccessToken.where(token: Digest::SHA256.hexdigest(@mcp_token))).to exist
end

# L2-E — reuse_access_token is off: a second consent mints a second token
When("the user authorizes that client again") do
  @sa_first_token = @mcp_token
  @sa_verifier = nil
  @sa_token_json = sa_authorize_and_exchange
  @mcp_token = @sa_token_json["access_token"]
end

Then("the second token should differ from the first and both should be live") do
  expect(@mcp_token).not_to eq(@sa_first_token)
  [@sa_first_token, @mcp_token].each { |raw| expect(Doorkeeper::AccessToken.by_token(raw)).to be_accessible }
end

# ── M6 — token endpoints ────────────────────────────────────────────────────

When("a script asks for a token for {string} with password {string}") do |email, password|
  sa_token_request("/users/tokens/sign_in", { email:, password: })
end

When("a script asks for a token for the user with password {string}") do |password|
  sa_token_request("/users/tokens/sign_in", { email: @user.email, password: })
end

Given("the user's account is locked") do
  @user.lock_access!(send_instructions: false)
end

When("someone tries to sign up {string} through the token API") do |email|
  sa_token_request("/users/tokens/sign_up", { email:, password: "Passw0rd!Strong", password_confirmation: "Passw0rd!Strong" })
end

Then("the token API should answer {int} with a token") do |status|
  expect(@sa_token_response.status).to eq(status), @sa_token_response.body
  expect(JSON.parse(@sa_token_response.body)["token"].presence || JSON.parse(@sa_token_response.body)["access_token"]).to be_present
end

Then("the token API should answer {int} with the error {string}") do |status, error|
  expect(@sa_token_response.status).to eq(status), @sa_token_response.body
  expect(JSON.parse(@sa_token_response.body)["error"]).to eq(error)
end

# M6-1 — the whole answer is kept, so the next request can be compared with it byte for byte
Then("the token API answer is remembered") do
  @sa_remembered = [@sa_token_response.status, JSON.parse(@sa_token_response.body)]
end

Then("the token API answer should be identical to the remembered one") do
  expect([@sa_token_response.status, JSON.parse(@sa_token_response.body)]).to eq(@sa_remembered)
end

Then("no user {string} should exist") do |email|
  expect(User.where(email:)).to be_none
end

# M6-4 — the website's forgot-password form, as submitted
When("someone asks for a password reset for {string}") do |email|
  @sa_reset = sa_client.tap do |session|
    session.post "/users/password", params: { user: { email: } }
    session.follow_redirect! if session.response.redirect?
  end.response
end

When("someone asks for a password reset for the user") do
  step %(someone asks for a password reset for "#{@user.email}")
end

Then("the password reset page should say {string}") do |text|
  expect(@sa_reset.body).to include(CGI.escapeHTML(text))
end

# M6-3 — reuses RackAttackClient (rack_attack_404_steps.rb): X-Forwarded-For makes the requests come
# from a real client IP rather than the safelisted loopback. The clock is frozen so every post lands
# in one throttle window (the @rack_attack hook travels back afterwards).
When("{string} posts to {string} {int} times") do |name, path, count|
  client = @rack_clients[name]
  freeze_time
  @sa_throttle_statuses = Array.new(count) do
    client.post(path, { email: "nobody-#{SecureRandom.hex(4)}@example.com", password: "wrong" }.to_json,
                { "CONTENT_TYPE" => "application/json", "HTTP_X_FORWARDED_FOR" => client.ip })
    client.last_response.status
  end
end

When("{int} visitors from different IPs ask for a token for {string}") do |count, email|
  freeze_time
  @sa_throttle_statuses = Array.new(count) do |index|
    client = RackAttackClient.new("203.0.113.#{index + 10}")
    client.post("/users/tokens/sign_in", { email:, password: "wrong" }.to_json,
                { "CONTENT_TYPE" => "application/json", "HTTP_X_FORWARDED_FOR" => client.ip })
    client.last_response.status
  end
end

Then("the first {int} posts should reach the app and the rest be throttled") do |allowed|
  expect(@sa_throttle_statuses.first(allowed)).not_to include(429)
  expect(@sa_throttle_statuses.drop(allowed)).to all(eq(429))
end
