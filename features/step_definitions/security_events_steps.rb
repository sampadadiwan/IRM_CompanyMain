# Steps for the security event trail (OWASP review 2026-11 M11, openspec/changes/archive/2026-11-10-security-event-trail):
#   features/security/security_events_sign_in.feature          (SI — business-rules §1, §2, §5, §7)
#   features/security/security_events_access.feature           (AC — §3, §4, §7)
#   features/security/security_events_screen.feature           (SC — §6)
#   features/security/security_events_tenant_isolation.feature (TI — §6 refusals)
#
# The people are the cast in business-rules.md "Shared setup": Golden Angels Fund (firm A) with Rahul and Meera
# (company admins), Priya (LP user, two-factor) and Karan (employee); Beta Capital (firm B) with Sara; CapHive
# support Anil and super Divya. Each is created on first mention, and the events their creation records (the
# roles setup_defaults gives) are cleared, so a scenario's assertions see only what its When steps did.
#
# Every request goes through a bare Rails integration session per person (a "browser"), so the hooks run exactly
# as in production — Warden, Devise, the controllers — with no JavaScript needed. Jobs run inline under Cucumber,
# so an event is in the table as soon as the request returns.
#
# Shared steps reused from elsewhere: mobile_api_steps.rb (the LP app), cross_region_steps.rb (regions).

module SecurityEventsWorld
  SE_FIRMS = {
    "Golden Angels Fund" => "Investment Fund",
    "Beta Capital" => "Investment Fund",
    "CapHive" => "Company"
  }.freeze

  # first name → last name, firm, extra roles, two-factor, phone, the IP their browser comes from
  SE_CAST = {
    "Rahul" => { last: "Mehta", firm: "Golden Angels Fund", roles: %i[company_admin], ip: "103.21.4.7" },
    "Meera" => { last: "Iyer", firm: "Golden Angels Fund", roles: %i[company_admin], ip: "103.21.4.8" },
    "Priya" => { last: "Shah", firm: "Golden Angels Fund", roles: %i[investor], tfa: :authenticator, phone: "9876543242", ip: "49.36.12.8" },
    "Karan" => { last: "Shah", firm: "Golden Angels Fund", roles: [], ip: "49.36.12.9" },
    # Support and super must use two-factor (M8, required from the deploy), so they have a method like real staff
    "Anil" => { last: "Kumar", firm: "CapHive", roles: %i[support], tfa: :authenticator, ip: "10.1.1.5" },
    "Divya" => { last: "Rao", firm: "CapHive", roles: %i[super], tfa: :authenticator, ip: "10.1.1.6" },
    "Sara" => { last: "Khan", firm: "Beta Capital", roles: %i[company_admin], ip: "122.15.3.3" }
  }.freeze

  # A password the scenarios type, distinctive enough to search every stored column for (X5)
  SE_PASSWORD = "Gold3n-Angels!42".freeze

  def se_firm(name)
    @se_firms ||= {}
    @se_firms[name] ||= Entity.find_by(name:) ||
                        FactoryBot.create(:entity, name:, entity_type: SE_FIRMS.fetch(name), enable_funds: true)
  end

  def se_email(first)
    spec = SE_CAST.fetch(first)
    "#{first.downcase}.#{spec[:last].downcase}@#{spec[:firm].parameterize}.test"
  end

  # The cast member (created on first use) — or any user named by email (the mobile steps' people)
  def se_user(name)
    return User.find_by!(email: name) if name.include?("@")

    @se_users ||= {}
    @se_users[name] ||= User.find_by(email: se_email(name)) || se_quietly { se_create_user(name) }
  end

  # Runs setup without leaving events behind: whatever it recorded is removed
  # (and the admin alerts it sent: the cast's own company_admin roles would otherwise email the other admins)
  def se_quietly
    before = SecurityEvent.maximum(:id).to_i
    mails_before = ActionMailer::Base.deliveries.size
    notices_before = Noticed::Event.maximum(:id).to_i
    result = yield
    SecurityEvent.where("id > ?", before).delete_all
    ActionMailer::Base.deliveries.slice!(mails_before..)
    alerts = Noticed::Event.where("id > ?", notices_before).where(type: "SecurityEventNotifier")
    Noticed::Notification.where(event_id: alerts.select(:id)).delete_all
    alerts.delete_all
    result
  end

  def se_create_user(name)
    spec = SE_CAST.fetch(name)
    user = FactoryBot.create(:user, entity: se_firm(spec[:firm]), first_name: name, last_name: spec[:last],
                                    email: se_email(name), password: SecurityEventsWorld::SE_PASSWORD)
    # Raw columns: a fixture number, not a user edit (the phone-change check guards edits)
    user.update_columns(call_code: "91", phone: spec[:phone]) if spec[:phone]
    spec[:roles].each { |role| se_grant_role(user, role) }
    user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "authenticator") if spec[:tfa] == :authenticator
    user.reload
  end

  def se_grant_role(user, role)
    if role.to_sym == :super
      # User#forbid_bad_role refuses add_role(:super) on purpose; production grants it in the DB
      role_row = Role.find_or_create_by!(name: "super")
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(["INSERT INTO users_roles (user_id, role_id) VALUES (?, ?)", user.id, role_row.id])
      )
    else
      user.add_role(role)
    end
    user.reload
  end

  def se_ip(name)
    name.include?("@") ? "127.0.0.1" : SE_CAST.fetch(name)[:ip]
  end

  # One browser per person; `fresh` starts a new one (a sign-in page visited while signed in redirects away)
  def se_browser(name, fresh: false)
    @se_browsers ||= {}
    @se_browsers.delete(name) if fresh
    @se_browsers[name] ||= ActionDispatch::Integration::Session.new(Rails.application)
  end

  # Every request carries the person's IP (and an optional browser name), as a real browser would
  def se_request(name, verb, path, params: {}, user_agent: nil, headers: {})
    browser = se_browser(name)
    headers = headers.merge("User-Agent" => user_agent) if user_agent
    browser.public_send(verb, path, params:, headers:, env: { "REMOTE_ADDR" => se_ip(name) })
    @se_last_browser = browser
    browser.response
  end

  # The page the person ends on, following redirects (a flash shows on the page after the redirect)
  def se_page_text(name)
    browser = se_browser(name)
    3.times do
      break unless browser.response.redirect?

      browser.follow_redirect!(env: { "REMOTE_ADDR" => se_ip(name) })
    end
    browser.response.body
  end

  def se_sign_in(name, password: SecurityEventsWorld::SE_PASSWORD, user_agent: nil)
    se_browser(name, fresh: true)
    se_request(name, :post, "/users/sign_in", params: { user: { email: se_user(name).email, password: } }, user_agent:)
    # CapHive support / super always answer the code step (M8): they are staff the scenarios act through, not the
    # subject of the sign-in scenarios (investors like Priya keep a separate code step, E-rows on wrong codes)
    se_answer_code(name) if se_user(name).two_factor_required? && se_browser(name).response.location.to_s.include?("/two_factor/new")
  end

  # Posts the current code; a code already used in this 30-second step is refused (anti-replay), so wait for the next
  def se_answer_code(name)
    user = se_user(name).reload
    travel(31.seconds) if user.consumed_timestep.to_i >= Time.now.to_i / 30
    se_request(name, :post, "/two_factor", params: { otp_code: user.current_otp })
  end

  # A sign-in that ends signed in: the password, then the current code for a two-factor user
  def se_sign_in_complete(name)
    se_sign_in(name)
    return if se_user(name).two_factor_mode.blank?

    se_request(name, :post, "/two_factor", params: { otp_code: se_user(name).reload.current_otp })
  end

  # Events recorded since the scenario's setup
  def se_events(kind = nil)
    scope = SecurityEvent.order(:id)
    kind ? scope.where(kind:) : scope
  end

  def se_one_event(kind, name = nil)
    scope = se_events(kind)
    scope = scope.where(user_id: se_user(name).id) if name
    events = scope.to_a
    expect(events.size).to eq(1), "expected one #{kind}#{" for #{name}" if name}, got #{events.size}: #{SecurityEvent.pluck(:kind, :user_id).inspect}"
    events.first
  end

  def se_name_of(user_id)
    return "none" if user_id.nil?

    User.with_deleted.find_by(id: user_id)&.first_name || user_id.to_s
  end

  # A field of the event as the scenario words it
  def se_field(event, field)
    case field
    when "firm" then event.entity_id ? Entity.find(event.entity_id).name : "none"
    when "account" then se_name_of(event.user_id)
    when "done by" then se_name_of(event.actor_id)
    when "on behalf of" then se_name_of(event.impersonator_id)
    when "door", "outcome", "category", "region", "ip_address", "kind" then event.public_send(field).to_s
    else (event.details || {})[field].to_s
    end
  end

  # Exactly one event of the kind (for the person, when named) whose fields all match the table — so a scenario
  # that signs in first can still pick out, say, the mail_addin sign-in
  def se_matching_event(kind, name, table)
    scope = se_events(kind)
    scope = scope.where(user_id: se_user(name).id) if name
    candidates = scope.to_a
    matches = candidates.select { |event| table.raw.all? { |field, expected| se_field(event, field) == expected } }
    seen = candidates.map { |event| table.raw.to_h { |field, _| [field, se_field(event, field)] } }
    expect(matches.size).to eq(1), "expected one #{kind}#{" for #{name}" if name} with #{table.raw.to_h}, saw #{seen.inspect}"
    matches.first
  end
end
World(SecurityEventsWorld)

# ── People and setup ─────────────────────────────────────────────────────────

Given("the security cast {string}") do |names|
  names.split(",").map(&:strip).each { |name| se_user(name) }
end

Given("{string} has failed {int} passwords in a row") do |name, count|
  se_user(name).update_columns(failed_attempts: count)
end

Given("{string} was locked {int} minutes ago") do |name, minutes|
  se_quietly { se_user(name).update_columns(locked_at: minutes.minutes.ago, failed_attempts: 6) }
end

# The admin console lists a firm's users only to a CapHive user mapped to it (BaseScope#resolve_admin)
Given("{string} supports the firm {string}") do |name, firm|
  entity = se_firm(firm)
  entity.permissions.set(:enable_support)
  entity.save!
  se_quietly do
    FactoryBot.create(:support_client_mapping, user: se_user(name), entity:, enabled: true,
                                               enable_user_login: true, end_date: Date.new(2027, 12, 31))
  end
end

Given("{string} is switched off as a user") do |name|
  se_user(name).update_columns(active: false)
end

Given("{string} has two-factor on with no method yet") do |name|
  se_quietly { se_user(name).update!(two_factor_enabled: true, two_factor_mode: nil) }
end

# E16 — the hourly count shared by the website and the app (TwoFactorVerifier), short of the limit
Given("{string} has already missed {int} two-factor codes this hour") do |name, count|
  count.times { TwoFactorVerifier.record_user_miss(se_user(name)) }
end

# E34 — Redis down (MISCONF / connection refused): enqueue raises
Given("the security event queue is down") do
  allow(SecurityEventWriteJob).to receive(:perform_later).and_raise(RedisClient::CannotConnectError, "connection refused")
end

# X3 — the queue and the table both fail
Given("the security event table cannot be written") do
  allow(SecurityEvent).to receive(:write!).and_raise(ActiveRecord::StatementInvalid, "disk full")
end

# E49 — the recorder itself breaks while building the event
Given("the security event recorder is broken") do
  allow(SecurityEventContext).to receive(:current).and_raise(NoMethodError, "boom")
end

Given("the application log is watched for security events") do
  @se_log_lines = []
  allow(Rails.logger).to receive(:warn).and_wrap_original do |original, *args, &block|
    @se_log_lines << (args.first || block&.call).to_s
    original.call(*args, &block)
  end
end

# ── Sign-in doors ────────────────────────────────────────────────────────────

When("{string} signs in on the website with the password {string}") do |name, password|
  se_sign_in(name, password:)
end

When("{string} signs in on the website with a {int}-character browser name") do |name, length|
  se_sign_in(name, user_agent: "Mozilla/5.0 #{'x' * length}"[0, length])
end

When("ghost@example.com tries to sign in on the website") do
  se_browser("Karan", fresh: true)
  se_request("Karan", :post, "/users/sign_in", params: { user: { email: "ghost@example.com", password: "anything" } })
end

When("a signed-out browser opens the funds page") do
  se_browser("Karan", fresh: true)
  se_request("Karan", :get, "/funds")
end

When("{string} enters the right two-factor code") do |name|
  se_request(name, :post, "/two_factor", params: { otp_code: se_user(name).reload.current_otp })
end

When("{string} enters a wrong two-factor code") do |name|
  # A code that is certainly not the current one
  wrong = se_user(name).reload.current_otp == "000000" ? "111111" : "000000"
  se_request(name, :post, "/two_factor", params: { otp_code: wrong })
end

When("{string} sets up the authenticator app at sign-in") do |name|
  se_sign_in(name)
  se_request(name, :post, "/two_factor/select_mode", params: { two_factor_mode: "authenticator" })
  se_request(name, :get, "/two_factor/enroll")
  se_request(name, :post, "/two_factor/verify_enrollment", params: { otp_code: se_user(name).reload.current_otp })
end

When("{string} opens a fresh sign-in link") do |name|
  signed_id = se_user(name).signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 10.minutes)
  se_browser(name, fresh: true)
  se_request(name, :get, "/users/no_password_login", params: { signed_id: })
end

# E8 — a support user (signed in) opens a client's sign-in link with no mapping that allows it
When("{string} opens the sign-in link of {string} without a delegation") do |actor, target|
  signed_id = se_user(target).signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 10.minutes)
  se_request(actor, :get, "/users/no_password_login", params: { signed_id: })
end

When("{string} opens a sign-in link that expired") do |name|
  signed_id = travel_to(30.minutes.ago) { se_user(name).signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 10.minutes) }
  se_browser(name, fresh: true)
  se_request(name, :get, "/users/no_password_login", params: { signed_id: })
end

When("{string} resets the password with a reset link") do |name|
  token = se_user(name).send(:set_reset_password_token)
  @se_secrets = (@se_secrets || []) << token
  se_browser(name, fresh: true)
  se_request(name, :put, "/users/password",
             params: { user: { reset_password_token: token, password: "N3w-Passw0rd!", password_confirmation: "N3w-Passw0rd!" } })
  @se_secrets << "N3w-Passw0rd!"
end

When("a password reset is requested for {string}") do |email_or_name|
  email = email_or_name.include?("@") ? email_or_name : se_user(email_or_name).email
  se_browser("Karan", fresh: true)
  se_request("Karan", :post, "/users/password", params: { user: { email: } })
end

When("{string} asks the token API for a token with the password {string}") do |name, password|
  se_browser(name, fresh: true)
  se_request(name, :post, "/users/tokens/sign_in", params: { email: se_user(name).email, password: },
                                                   headers: { "Accept" => "application/json" })
end

When("{string} changes their own password in the profile") do |name|
  se_sign_in(name)
  se_request(name, :patch, "/users", params: { user: { current_password: SecurityEventsWorld::SE_PASSWORD, password: "Pr0file-Pass!", password_confirmation: "Pr0file-Pass!" } })
end

# H15 — what PhoneChangeConfirm does once the emailed code matches
When("{string} confirms a new phone number ending {string}") do |name, last_two|
  se_user(name).apply_verified_phone_change!(call_code: "91", phone: "98765432#{last_two}", audit_comment: "Phone changed")
end

When("{string} resets the two-factor method of {string}") do |actor, target|
  se_sign_in(actor)
  se_request(actor, :post, "/users/#{se_user(target).id}/reset_two_factor")
end

When("{string} turns their own two-factor off with their password and code") do |name|
  se_sign_in(name)
  se_request(name, :post, "/two_factor", params: { otp_code: se_user(name).reload.current_otp })
  # The sign-in code is used up; the turn-off needs the next one (TOTP replay protection)
  travel 31.seconds
  se_request(name, :post, "/users/#{se_user(name).id}/disable_two_factor",
             params: { password: SecurityEventsWorld::SE_PASSWORD, otp_code: se_user(name).reload.current_otp })
end

When("{string} switches {string} off in the admin console") do |actor, target|
  se_sign_in(actor)
  se_request(actor, :patch, "/admin/users/#{se_user(target).id}", params: { user: { active: "0" } })
end

When("{string} deactivates the firm {string}") do |actor, firm|
  se_sign_in(actor)
  se_request(actor, :patch, "/entities/#{se_firm(firm).id}/deactivate", params: { confirm_deactivate: "1" })
end

When("{string} signs out of the website") do |name|
  se_request(name, :put, "/users/sign_out")
end

# H7 / E11 — a region switch: the link is minted in IN and redeemed in US (the cross_region steps set both up)
When("{string} arrives in {string} with a region-switch link") do |name, region|
  token = CrossSiteLink.new.generate(se_user(name).email, purpose: CrossSiteLink::PURPOSE, site: region, from: "IN")
  ENV["CURRENT_SITE"] = region
  SiteRegistry.reset!
  se_browser(name, fresh: true)
  se_request(name, :get, "/users/cross_site_login", params: { token:, from: "IN" })
end

When("{string} arrives in {string} with a region-switch link that expired") do |name, region|
  token = travel_to(1.hour.ago) { CrossSiteLink.new.generate(se_user(name).email, purpose: CrossSiteLink::PURPOSE, site: region, from: "IN") }
  ENV["CURRENT_SITE"] = region
  SiteRegistry.reset!
  se_browser(name, fresh: true)
  se_request(name, :get, "/users/cross_site_login", params: { token:, from: "IN" })
end

When("{string} opens an app-to-website hand-off link") do |name|
  token = CrossSiteLink.new.generate(se_user(name).email, purpose: Api::Mobile::V1::WebHandoffsController::PURPOSE,
                                                          site: SiteRegistry.current_code, from: SiteRegistry.current_code)
  se_browser(name, fresh: true)
  se_request(name, :get, "/users/mobile_handoff", params: { token:, path: "/" })
end

When("{string} connects the Outlook add-in") do |name|
  se_sign_in(name)
  se_request(name, :post, "/outlook_addin/oauth_start")
end

When("an MCP request comes with a revoked token of {string}") do |name|
  app = Doorkeeper::Application.create!(name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback", scopes: "read", confidential: false)
  token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: se_user(name).id, scopes: "read", expires_in: 1.hour.to_i)
  plaintext = token.plaintext_token
  token.revoke
  @se_secrets = (@se_secrets || []) << plaintext
  se_browser(name, fresh: true)
  se_request(name, :post, "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                                  headers: { "Authorization" => "Bearer #{plaintext}", "Content-Type" => "application/json" })
end

When("an MCP request comes with no token") do
  se_browser("Karan", fresh: true)
  se_request("Karan", :post, "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                                     headers: { "Content-Type" => "application/json" })
end

# E14 — an add-in token minted while the user was in another firm
When("the mail add-in calls with a token of {string} minted for {string}") do |name, firm|
  token = MailAddinToken.issue_for(se_user(name))
  token.update_column(:entity_id, se_firm(firm).id)
  se_browser(name, fresh: true)
  se_request(name, :get, "/api/v1/mail/owners", headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Accept" => "application/json" })
end

# ── Recorder and writer ──────────────────────────────────────────────────────

When("the write job for that {string} event runs again") do |kind|
  event = se_one_event(kind)
  attrs = event.attributes.slice(*SecurityEvent.column_names).except("id", "created_at")
  attrs["occurred_at"] = event.occurred_at.utc.iso8601(6)
  SecurityEventWriteJob.perform_now(attrs)
end

When("a hook records the unknown kind {string}") do |kind|
  @se_record_result = SecurityEvents.record(kind, user: se_user("Karan"))
end

When("a role grant to {string} is recorded with an extra token detail") do |name|
  @se_record_result = SecurityEvents.record("role.granted", user: se_user(name), details: { role: "approver", token: "tok_live_123" })
end

When("someone tries to change that {string} event") do |kind|
  event = se_one_event(kind)
  @se_changed_event_id = event.id
  begin
    event.update(kind: "sign_in.failed")
    @se_error = nil
  rescue ActiveRecord::ReadOnlyRecord => e
    @se_error = e
  end
end

# ── Assertions ───────────────────────────────────────────────────────────────

Then("a security event {string} is recorded for {string}") do |kind, name|
  se_one_event(kind, name)
end

Then("a security event {string} is recorded for {string} with:") do |kind, name, table|
  se_matching_event(kind, name, table)
end

Then("a security event {string} is recorded with:") do |kind, table|
  se_matching_event(kind, nil, table)
end

Then("no security event {string} is recorded") do |kind|
  expect(se_events(kind).count).to eq(0), "expected no #{kind}, got #{se_events(kind).pluck(:kind, :user_id, :details).inspect}"
end

Then("no security event is recorded") do
  expect(SecurityEvent.count).to eq(0), "expected none, got #{SecurityEvent.pluck(:kind, :user_id).inspect}"
end

Then("exactly {int} security event(s) {string} is/are recorded") do |count, kind|
  expect(se_events(kind).count).to eq(count)
end

Then("no security event {string} is recorded for {string}") do |kind, name|
  expect(se_events(kind).where(user_id: se_user(name).id).count).to eq(0)
end

# E15 — the third of several code failures
Then("a security event {string} is recorded for {string} with attempt {int} ending the challenge") do |kind, name, attempt|
  event = se_events(kind).where(user_id: se_user(name).id).detect { |e| e.details["attempt"] == attempt }
  expect(event).to be_present, "no #{kind} with attempt #{attempt}: #{se_events(kind).pluck(:details).inspect}"
  expect(event.details["challenge_ended"]).to be(true)
end

Then("that {string} event happened just now") do |kind|
  expect(se_one_event(kind).occurred_at).to be_within(1.minute).of(Time.current)
end

Then("that {string} event has no account, no firm and only the digest of {string}") do |kind, email|
  event = se_one_event(kind)
  expect([event.user_id, event.entity_id]).to eq([nil, nil])
  expect(event.identifier_digest).to eq(SecurityEventContext.identifier_digest(email))
  # The address itself is in no column
  expect(event.attributes.values.join(" ")).not_to include(email)
end

Then("that {string} event stores a {int}-character browser name") do |kind, length|
  expect(se_one_event(kind).user_agent.length).to eq(length)
end

Then("that {string} event holds only the detail {string}") do |kind, key|
  expect(se_one_event(kind).details.keys).to eq([key])
end

Then("the security event is refused as read-only") do
  expect(@se_error).to be_a(ActiveRecord::ReadOnlyRecord)
  # The row in the table is unchanged
  expect(SecurityEvent.find(@se_changed_event_id).kind).to eq("sign_in.succeeded")
end

Then("the recorder returned nothing and logged {string}") do |text|
  expect(@se_record_result).to be_nil
  expect(@se_log_lines.join("\n")).to include(text)
end

Then("the security log says {string}") do |text|
  expect(@se_log_lines.join("\n")).to include(text)
end

Then("one security log line names {string} and the user {string} and the IP") do |kind, name|
  line = @se_log_lines.find { |l| l.include?("[security_event] lost") }
  expect(line).to be_present, "no [security_event] lost line in #{@se_log_lines.inspect}"
  expect(line).to include(kind, %("user_id":#{se_user(name).id}), se_ip(name))
end

Then("{string} ends up signed in") do |name|
  browser = se_browser(name)
  browser.get "/users/#{se_user(name).id}", env: { "REMOTE_ADDR" => se_ip(name) }
  expect(browser.response.status).to eq(200), "expected a signed-in page, got #{browser.response.status} → #{browser.response.location}"
end

Then("{string} sees {string}") do |name, text|
  expect(se_page_text(name)).to include(text)
end

Then("the request of {string} is answered with {int}") do |name, status|
  expect(se_browser(name).response.status).to eq(status)
end

# X5 — no secret the scenario used (a password, a reset token, a bearer token, the session id, a signed id) is in
# any column of any event
Then("no security event holds a secret") do
  secrets = [SecurityEventsWorld::SE_PASSWORD, "Pr0file-Pass!", *Array(@se_secrets)].compact_blank
  (@se_browsers || {}).each_value do |browser|
    cookie = browser.cookies.to_hash.values.join(" ")
    secrets << cookie if cookie.present?
  end
  stored = SecurityEvent.all.flat_map { |e| e.attributes.values.map { |v| v.is_a?(Hash) ? v.to_json : v.to_s } }.join(" | ")
  expect(SecurityEvent.count).to be_positive
  secrets.each { |secret| expect(stored).not_to include(secret) }
end

# ── Phase 2: access, support, credentials, exports ──────────────────────────

Given("{string} holds the role {string}") do |name, role|
  se_quietly { se_user(name).add_role(role.to_sym) }
end

Given("{string} has Enable support switched off") do |name|
  se_user(name).update_columns(enable_support: false)
end

Given("{string}, {string} and {string} have Enable support switched on") do |a, b, c|
  [a, b, c].each { |name| se_user(name).update_columns(enable_support: true) }
end

# The roles field of the user form: every updatable role the admin leaves ticked (UsersController#update)
When("{string} saves the roles of {string} as {string}") do |actor, target, roles|
  se_sign_in(actor)
  role_name = roles.split(",").map(&:strip).presence || [""]
  se_request(actor, :patch, "/users/#{se_user(target).id}", params: { user: { first_name: se_user(target).first_name, role_name: } })
end

When("{string} turns on Enable support on their own profile") do |name|
  se_sign_in(name)
  se_request(name, :patch, "/users/#{se_user(name).id}", params: { user: { enable_support: "1" } })
end

When("{string} uses Login as on {string}") do |actor, target|
  se_sign_in(actor)
  se_request(actor, :post, "/users/#{se_user(target).id}/login_as")
end

When("{string} opens the sign-in link of {string} as support") do |actor, target|
  se_sign_in(actor)
  signed_id = se_user(target).signed_id(purpose: User::MAGIC_LINK_PURPOSE, expires_in: 10.minutes)
  se_request(actor, :get, "/users/no_password_login", params: { signed_id: })
end

When("{string} switches into {string} and back") do |name, firm|
  mapping = SupportClientMapping.find_by!(user_id: se_user(name).id, entity_id: se_firm(firm).id)
  se_sign_in(name)
  se_request(name, :patch, "/support_client_mappings/#{mapping.id}/switch")
  se_request(name, :patch, "/support_client_mappings/#{mapping.id}/revert")
end

# E23 — what an import job does: it runs as the importer (ApplicationJob restores Current.user), with no request
When("an import run by {string} creates the employee {string} in {string}") do |actor, email, firm|
  Current.set(user: se_user(actor)) do
    FactoryBot.create(:user, entity: se_firm(firm), email:, first_name: "Neel", last_name: "Rao")
  end
end

# E24 — a grant inside a transaction that rolls back
When("a grant of {string} to {string} is rolled back") do |role, name|
  ActiveRecord::Base.transaction do
    se_user(name).add_role(role.to_sym)
    raise ActiveRecord::Rollback
  end
end

# E26 — an approved investor access for someone with no account creates the LP user (InvestorAccess#update_user)
When("an investor access for {string} is approved in {string}") do |email, firm|
  fund_manager = se_firm(firm)
  investor_entity = FactoryBot.create(:entity, name: "Lena Family Office", entity_type: "Investor")
  investor = FactoryBot.create(:investor, entity: fund_manager, investor_entity:, investor_name: "Lena Family Office")
  FactoryBot.create(:investor_access, entity: fund_manager, investor:, user: nil, email:, first_name: "Lena",
                                      last_name: "Shah", approved: true)
end

When("support is switched off for everyone") do
  User.disable_support_for_all
end

# E28 — the support user, signed in as the client, changes her number through the emailed-code flow
When("{string}, signed in as {string}, changes her phone to end in {string}") do |actor, target, last_two|
  step %("#{actor}" uses Login as on "#{target}")
  user = se_user(target)
  se_request(actor, :post, "/users/#{user.id}/phone_change", params: { call_code: "91", phone: "98765432#{last_two}" })
  se_request(actor, :patch, "/users/#{user.id}/phone_change", params: { code: emailed_phone_change_code(user.email) })
end

When("{string} creates the API key {string}") do |name, key_name|
  se_sign_in(name)
  se_request(name, :post, "/users/api_tokens", params: { api_token: { name: key_name } })
  @se_secrets = (@se_secrets || []) + Devise::Api::Token.where(resource_owner_id: se_user(name).id).pluck(:access_token, :refresh_token).flatten
end

When("{string} revokes the API key {string}") do |name, key_name|
  token = ApiToken.find_by!(user_id: se_user(name).id, name: key_name)
  se_request(name, :delete, "/users/api_tokens/#{token.id}")
end

Given("{string} already has {int} live API keys") do |name, count|
  se_quietly { count.times { |i| ApiToken.mint!(user: se_user(name), name: "Key #{i + 1}") } }
end

# H24 — the phone is signed in (registry), then the person signs it out from the website's Devices page
When("{string} signs the phone {string} out from the website") do |name, phone_name|
  device = se_quietly { mobile_sign_in!(se_user(name), phone_name) }
  se_sign_in_complete(name)
  se_request(name, :delete, "/users/mobile_devices/#{device.id}")
end

# H25 — the OAuth consent screen: show, then Authorize (PKCE, as Claude.ai sends it)
When("{string} authorises the connected app {string}") do |name, app_name|
  app = Doorkeeper::Application.create!(name: app_name, redirect_uri: "https://claude.ai/api/mcp/auth_callback", scopes: "read", confidential: false)
  verifier = SecureRandom.urlsafe_base64(48)
  params = { client_id: app.uid, redirect_uri: app.redirect_uri, response_type: "code", scope: "read", state: "se",
             code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false), code_challenge_method: "S256" }
  se_sign_in(name)
  se_request(name, :get, "/oauth/authorize", params:)
  se_request(name, :post, "/oauth/authorize", params:)
end

When("{string} downloads {string} as a spreadsheet") do |name, path|
  se_sign_in_complete(name)
  se_request(name, :get, path, headers: { "Referer" => "http://www.example.com/" })
end

When("{string} downloads the folder {string}") do |name, folder_name|
  folder = se_quietly { FactoryBot.create(:folder, entity: se_user(name).entity, name: folder_name) }
  # The zip itself is built by DocumentDownloadJob (covered by its own features); inline under Cucumber it would
  # write from this GET's read-only connection, so only the request — and its event — is exercised here
  allow(DocumentDownloadJob).to receive(:perform_later)
  se_sign_in(name)
  se_request(name, :get, "/folders/#{folder.id}/download")
end

When("{string} asks for a data dump of {string}") do |name, firm|
  se_firm(firm).entity_setting.update_columns(db_dumps_enable: true)
  se_sign_in(name)
  se_request(name, :post, "/entities/#{se_firm(firm).id}/db_dump")
end

# ── Phase 3: the screen, alerts, the weekly pack, retention ─────────────────

module SecurityEventsScreenWorld
  # The page as Capybara sees it, from the person's last response (following redirects)
  def se_page(name)
    Capybara.string(se_page_text(name))
  end

  # Mail delivered to a person (or an address) whose subject includes `subject` (jobs run inline)
  def se_mails_to(name_or_email, subject = nil)
    email = name_or_email.include?("@") && !SecurityEventsWorld::SE_CAST.key?(name_or_email) ? name_or_email : se_user(name_or_email).email
    ActionMailer::Base.deliveries.select { |mail| mail.to.to_a.include?(email) && (subject.nil? || mail.subject.to_s.include?(subject)) }
  end

  # The rows of an emailed spreadsheet's sheet, header first
  def se_xlsx_rows(mail, sheet = nil)
    attachment = mail.attachments.find { |a| a.filename.end_with?(".xlsx") }
    expect(attachment).to be_present, "no xlsx attached to #{mail.subject}"
    file = Tempfile.new(["se", ".xlsx"])
    file.binmode
    file.write(attachment.decoded)
    file.close
    book = Roo::Excelx.new(file.path)
    @se_sheet_names = book.sheets
    book.sheet(sheet || book.sheets.first).to_a
  ensure
    file&.unlink
  end
end
World(SecurityEventsScreenWorld)

# Times in the app time zone, e.g. "2026-11-09 12:00"
Given("today is {string} for the security trail") do |time|
  travel_to Time.zone.parse(time)
end

# Seeds events straight into the table (the screen, the pack and retention read rows, however they were written)
Given("security events in the trail:") do |table|
  table.hashes.each do |row|
    account = row["account"].presence
    actor = row["done by"].presence
    user = account && account != "ghost" ? se_user(account) : nil
    SecurityEvent.create!(
      uid: SecureRandom.uuid, kind: row["kind"], category: SecurityEventCatalogue.fetch(row["kind"])[:category],
      outcome: row["outcome"].presence || "success", door: row["door"].presence || "web_password",
      user_id: user&.id, actor_id: actor ? se_user(actor).id : nil,
      entity_id: if row["firm"].to_s == "none"
                   nil
                 else
                   (row["firm"].present? ? se_firm(row["firm"]).id : user&.entity_id)
                 end,
      identifier_digest: account == "ghost" ? SecurityEventContext.identifier_digest("ghost@example.com") : nil,
      ip_address: row["ip"].presence || "49.36.12.8", user_agent: row["browser"].presence || "Mozilla/5.0",
      region: "IN", details: row["details"].present? ? JSON.parse(row["details"]) : {},
      occurred_at: Time.zone.parse(row["when"]), created_at: Time.current
    )
  end
end

# The viewer's own sign-in is setup here, not part of what the list should show
When("{string} opens Security Events") do |name|
  se_quietly { se_sign_in_complete(name) }
  se_request(name, :get, "/security_events")
end

When("{string} opens Security Events with {string}") do |name, query|
  se_quietly { se_sign_in_complete(name) }
  se_request(name, :get, "/security_events?#{query}")
end

When("{string} downloads the security events with {string}") do |name, query|
  se_quietly { se_sign_in_complete(name) }
  se_request(name, :get, "/security_events.xlsx?#{query}")
end

# X11 — no write route exists; the router refuses before any controller (show_exceptions is off in tests)
When("{string} sends {string} to {string}") do |name, verb, path|
  se_sign_in_complete(name)
  begin
    se_request(name, verb.downcase.to_sym, path)
    @se_route_status = se_browser(name).response.status
  rescue ActionController::RoutingError
    @se_route_status = 404
  end
end

When("the Monday security pack runs for {string}") do |date|
  SecurityEventWeeklyPackJob.perform_now(date)
end

When("the nightly security purge runs") do
  SecurityEventPurgeJob.perform_now
end

Given("the weekly pack goes to {string}") do |email|
  @se_saved_weekly_to = ENV.fetch(SecurityEventWeeklyPackJob::SETTING, nil) unless defined?(@se_saved_weekly_to)
  ENV[SecurityEventWeeklyPackJob::SETTING] = email
end

Given("the weekly pack has no recipient set") do
  @se_saved_weekly_to = ENV.fetch(SecurityEventWeeklyPackJob::SETTING, nil) unless defined?(@se_saved_weekly_to)
  ENV.delete(SecurityEventWeeklyPackJob::SETTING)
end

After do
  # Put the region's setting back exactly as it was, so nothing leaks to the next scenario in this worker
  if defined?(@se_saved_weekly_to)
    @se_saved_weekly_to.nil? ? ENV.delete(SecurityEventWeeklyPackJob::SETTING) : ENV[SecurityEventWeeklyPackJob::SETTING] = @se_saved_weekly_to
  end
end

Given("{string} is no longer an active user") do |name|
  se_user(name).update_columns(active: false)
end

Given("the firm {string} has support switched off") do |firm|
  entity = se_firm(firm)
  entity.permissions.unset(:enable_support)
  entity.save!
end

When("an import run by {string} gives {string} the role {string}") do |actor, name, role|
  Current.set(user: se_user(actor)) { se_user(name).add_role(role.to_sym) }
end

Then("{string} sees the Security Events list with {int} row(s)") do |name, count|
  page = se_page(name)
  expect(page).to have_css("h1", text: "Security Events")
  expect(page.all("table#security_events tbody tr").size).to eq(count)
end

Then("{string} sees only events of {string}") do |name, firms|
  page = se_page(name)
  shown = page.all("table#security_events tbody tr").map { |tr| tr.all("td")[1].text.squish }.uniq.sort
  expect(shown).to eq(firms.split(",").map(&:strip).sort)
end

Then("the Security Events list of {string} has the events {string}") do |name, labels|
  page = se_page(name)
  # The Event column: the 2nd cell (3rd when a Firm column is shown)
  index = page.has_css?("table#security_events thead th", text: "Firm") ? 2 : 1
  shown = page.all("table#security_events tbody tr").map { |tr| tr.all("td")[index].text.squish }
  expect(shown).to eq(labels.split(";").map(&:strip))
end

Then("{string} sees the security card {string} at {int}") do |name, subtitle, count|
  page = se_page(name)
  card = page.all("#security_event_grid_stats .card").find { |c| c.has_css?(".card-subtitle", text: subtitle) }
  expect(card).to be_present, "no card #{subtitle}"
  expect(card.find("h2").text.strip).to eq(count.to_s)
end

Then("{string} sees the help {string}") do |name, text|
  expect(se_page(name).text.squish).to include(text)
end

# U.1 — what to do is suggested per row, not in a general help line under the title
Then("{string} sees no general help line above the cards") do |name|
  expect(se_page(name)).to have_no_css("#security_events_help", visible: :all)
end

# U.1b — the popup a row's bulb opens: found through the row's own button, so a wrong target fails here
def se_advice_popup(name, label)
  page = se_page(name)
  row = page.all("#security_events tbody tr").find { |tr| tr.text.squish.include?(label) }
  expect(row).not_to be_nil, "no row with #{label.inspect}"
  target = row.find("button.security-event-advice")["data-bs-target"]
  page.find(target, visible: :all)
end

Then("the What to do popup of the {string} row of {string} says {string}") do |label, name, text|
  expect(se_advice_popup(name, label).text(:all).squish).to include(text)
end

Then("every row's What to do button of {string} opens its own popup") do |name|
  page = se_page(name)
  targets = page.all("button.security-event-advice").pluck("data-bs-target")
  expect(targets).not_to be_empty
  expect(targets.uniq.size).to eq(targets.size)
  targets.each { |t| expect(page).to have_css(t, visible: :all) }
end

# U.1b — the catalogue has a suggestion for every kind, so no row falls back to the general default
Then("every security event kind has its own What to do suggestion") do
  expect(SecurityEventCatalogue::ADVICE.keys).to match_array(SecurityEventCatalogue.kinds)
end

Then("{string} sees a tooltip {string}") do |name, text|
  titles = se_page(name).all("[data-bs-toggle='tooltip']", visible: :all).map { |el| el[:title].to_s }
  expect(titles.any? { |t| t.include?(text) }).to be(true), "no tooltip with #{text.inspect} in #{titles.inspect}"
end

Then("the security menu entry is shown to {string}") do |name|
  se_sign_in_complete(name)
  se_request(name, :get, "/users/#{se_user(name).id}")
  expect(se_page(name)).to have_css("a#security_events_menu", text: "Security Events", visible: :all)
end

Then("the security menu entry is not shown to {string}") do |name|
  se_sign_in_complete(name)
  se_request(name, :get, "/users/#{se_user(name).id}")
  expect(se_page(name)).to have_no_css("a#security_events_menu", visible: :all)
end

Then("{string} is emailed a security spreadsheet with {int} event row(s) of {string}") do |name, count, firm|
  mail = se_mails_to(name, "Your security events spreadsheet").last
  expect(mail).to be_present, "no spreadsheet email to #{name}: #{ActionMailer::Base.deliveries.map(&:subject).inspect}"
  rows = se_xlsx_rows(mail)
  expect(rows.size - 1).to eq(count)
  expect(rows.drop(1).pluck(1).uniq).to eq([firm]) if count.positive?
  @se_last_rows = rows
end

Then("the spreadsheet's browser cell starts with {string}") do |prefix|
  header = @se_last_rows.first
  cell = @se_last_rows.drop(1).first[header.index("Browser")]
  expect(cell).to start_with(prefix)
end

Then("{string} gets the security alert {string}") do |name, headline|
  mails = se_mails_to(name, "Security alert: #{headline}")
  expect(mails.size).to eq(1), "#{name}: #{ActionMailer::Base.deliveries.map { |m| [m.to, m.subject] }.inspect}"
  # The bell, with the same sentence
  bell = Noticed::Notification.where(recipient: se_user(name)).joins(:event).where(noticed_events: { type: "SecurityEventNotifier" })
  expect(bell.count).to eq(1)
  @se_alert_mail = mails.first
end

# H33 / E42 — support visits: the bell, with the headline, and no email at all (user decision 2026-11-09)
Then("{string} gets the bell {string} and no email") do |name, headline|
  bells = Noticed::Notification.where(recipient: se_user(name)).joins(:event).where(noticed_events: { type: "SecurityEventNotifier" }).to_a
  expect(bells.size).to eq(1), "#{name}: #{bells.size} security bells"
  expect(bells.first.message).to eq(headline)
  expect(se_mails_to(name, "Security alert")).to be_empty
end

Then("the security alert says {string}") do |text|
  expect(@se_alert_mail.body.encoded.squish).to include(text)
end

Then("no security alert is sent") do
  expect(ActionMailer::Base.deliveries.map(&:subject).grep(/Security alert/)).to be_empty
  expect(Noticed::Event.where(type: "SecurityEventNotifier").count).to eq(0)
end

Then("exactly {int} security alert(s) is/are sent to {string}") do |count, name|
  expect(se_mails_to(name, "Security alert").size).to eq(count)
end

Then("{string} is emailed the pack {string} with the sheets {string}") do |email, subject, sheets|
  mail = se_mails_to(email, subject).last
  expect(mail).to be_present, "no pack: #{ActionMailer::Base.deliveries.map { |m| [m.to, m.subject] }.inspect}"
  expect(mail.subject).to eq(subject)
  @se_pack_mail = mail
  se_xlsx_rows(mail)
  expect(@se_sheet_names).to eq(sheets.split(",").map(&:strip))
end

Then("the pack's {string} sheet has {int} event row(s)") do |sheet, count|
  expect(se_xlsx_rows(@se_pack_mail, sheet).size - 1).to eq(count)
end

Then("the pack's failed sign-ins sheet counts {int} for {string} on {string}") do |count, name, day|
  rows = se_xlsx_rows(@se_pack_mail, "Failed sign-ins by account")
  row = rows.drop(1).find { |r| r[1].to_s.start_with?(se_user(name).full_name) && r[2] == day }
  expect(row).to be_present, rows.inspect
  expect(row[3].to_i).to eq(count)
end

Then("no security pack is emailed") do
  expect(ActionMailer::Base.deliveries.map(&:subject).grep(/Security events/)).to be_empty
end

Then("the security trail keeps the events of {string} and not {string}") do |kept, gone|
  times = SecurityEvent.pluck(:occurred_at).map { |t| t.in_time_zone.strftime("%Y-%m-%d %H:%M:%S") }
  kept.split(",").map(&:strip).each { |t| expect(times).to include(Time.zone.parse(t).strftime("%Y-%m-%d %H:%M:%S")) }
  gone.split(",").map(&:strip).each { |t| expect(times).not_to include(Time.zone.parse(t).strftime("%Y-%m-%d %H:%M:%S")) }
end

Then("the write route answer is 404 and the event is unchanged") do
  expect(@se_route_status).to eq(404)
  expect(SecurityEvent.count).to be_positive
end

# E52 — the Event label is a link to the same list filtered by that kind (in the frame)
When("{string} clicks the event {string}") do |name, label|
  link = se_page(name).all("a.security-event-kind-link", text: label).first
  expect(link).to be_present, "no event link #{label.inspect}"
  expect(link["data-turbo-frame"]).to eq("security_events_frame")
  se_request(name, :get, link[:href])
end

When("{string} clears the event filter") do |name|
  chip = se_page(name).find("#security_events_kind_chip")
  se_request(name, :get, chip[:href])
end

Then("the Event filter of {string} shows {string} with the account {string}") do |name, label, account|
  page = se_page(name)
  expect(page.find("#q_kind_eq option[selected]").text).to eq(label)
  expect(page.find("#account").value).to eq(account)
  expect(page.find("#security_events_kind_chip").text.squish).to include(label)
  # The download carries the same filter
  expect(page.find("#security_events_download")[:href]).to include("kind_eq", "account=#{account}")
end
