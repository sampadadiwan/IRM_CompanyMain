# frozen_string_literal: true

# Security review 2026-10, "Authentication and session — Medium / Low": M3, M4 (incl. N6), M5, L3,
# L4, L5, L7, L8. Design: docs/security/security_review_2026_10.md.
#
# Reused from elsewhere:
#   login.rb / common.rb       — "Im logged in as a user …", "the user has role …", "the user has curr
#                                role …", "I am at the login page", "I set my new password to …",
#                                "I should see …", "I should not see …"
#   two_factor_steps.rb        — two-factor setup, "I should be on the 2FA verification page",
#                                "I should be redirected to the login page"
#   api_json_steps.rb          — Profile API tokens, "{name} sends GET …", "the API status is …"
#   mcp_transport_steps.rb     — MCP enablement, the MCP access token and client
#   entity_deactivation_steps.rb — "the deactivation job for … runs the way Sidekiq runs it"
#   cross_region_steps.rb / cross_region_login_steps.rb — regions, the region user, handoff_session
#   security_c5_c6_steps.rb    — the New User form posts and checks (L7-2)

module SecurityAuthBHelpers
  # A support user with an enabled login-as mapping on the user's firm, signed in on a fresh
  # integration session that has started impersonating `user` through UsersController#login_as —
  # the real flow, so session[:support_user_id] is set exactly as in production.
  def impersonation_session_for(user, host: nil)
    support_entity = FactoryBot.create(:entity, entity_type: "Investment Fund")
    support_user = FactoryBot.create(:user, entity: support_entity)
    support_user.add_role :support
    # A blank user_emails list admits any support user; enable_user_login carries UserPolicy#login_as?
    FactoryBot.create(:support_client_mapping, user: support_user, entity: user.entity,
                                               enabled: true, enable_user_login: true)

    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.host = host if host
    # M8 — support answers the two-factor code step, and Login as needs their verified method
    integration_sign_in(session, support_user)
    session.post "/users/#{user.id}/login_as"
    expect(session.session[:support_user_id]).to eq(support_user.id), "impersonation did not start"
    session
  end

  # The redirect target's path of an integration-session response
  def redirect_path_of(response)
    URI(response.headers["Location"].to_s).path
  end

  # The CSP log captured by the L5-1 step
  def csp_log
    @csp_log_io&.string.to_s
  end
end
World(SecurityAuthBHelpers)

# ---- M3 / L3 ------------------------------------------------------------------------------------

When('the user opens their emailed password reset link') do
  # The same raw token the "Change my password" link carries (Devise emails it and returns it)
  raw = @user.send_reset_password_instructions
  visit edit_user_password_path(reset_password_token: raw)
end

When('I sign in with the password {string}') do |password|
  fill_in('user_email', with: @user.email)
  fill_in('user_password', with: password)
  click_on("Log In")
end

Given('the user is a system-created user on their first login') do
  # User#reset_password? is sign_in_count == 1 && system_created; set after any login so it holds
  @user.update_columns(system_created: true, sign_in_count: 1)
end

When('I press {string} on the first-login banner') do |button|
  visit "/"
  click_on(button)
end

When('I post the first-login password reset') do
  page.driver.submit :post, reset_password_users_path, {}
end

Then('I am on the set-new-password form') do
  expect(page).to have_current_path(%r{\A/users/password/edit})
  expect(page).to have_field("user_password")
end

Then('I am sent to the change-password page') do
  expect(page).to have_current_path("/users/edit")
end

Then('the user has a password reset token') do
  expect(@user.reload.reset_password_token).to be_present
end

Then('the user has no password reset token') do
  expect(@user.reload.reset_password_token).to be_nil
end

When('a support user impersonating the user posts the first-login password reset') do
  @impersonation = impersonation_session_for(@user)
  # login_as signed the user in, which bumped sign_in_count; put the first-login state back so the
  # refusal below can only come from the impersonation check
  @user.update_columns(sign_in_count: 1)
  @impersonation.post "/users/reset_password"
end

Then('the impersonated request is sent to the change-password page') do
  expect(@impersonation.response.status).to eq(302)
  expect(redirect_path_of(@impersonation.response)).to eq("/users/edit")
end

# ---- M4 -----------------------------------------------------------------------------------------

When('an admin deactivates the user') do
  # A saved update (as the user page does), so User#revoke_bearer_credentials runs
  @user.update!(active: false)
end

When('the user changes their password to {string}') do |password|
  @user.update!(password:, password_confirmation: password)
end

Given('the user also has a token from the token sign-in endpoint') do
  # The kind POST /users/tokens/sign_in mints: a devise-api token wrapped by no ApiToken or phone
  token = Devise::Api::Token.create!(resource_owner: @user,
                                     access_token: Devise::Api::Token.generate_uniq_access_token(@user),
                                     refresh_token: Devise::Api::Token.generate_uniq_refresh_token(@user),
                                     expires_in: 1.day.to_i)
  @sign_in_token_client = ApiJsonClient.new
  @sign_in_token_client.access_token = token.access_token
end

Then('the sign-in token is refused on GET {string}') do |path|
  expect(@sign_in_token_client.call(:get, path).status).to eq(401)
end

Then("the user's MCP access token is revoked") do
  expect(Doorkeeper::AccessToken.where(resource_owner_id: @user.id, revoked_at: nil)).to be_none
end

# ---- M5 -----------------------------------------------------------------------------------------

When('a support user impersonating that user starts a switch to {string}') do |code|
  host = URI(SiteRegistry.url_for(SiteRegistry.current_code)).host
  # handoff_session (cross_region_login_steps.rb) is what the selector checks below read
  @handoff_session = impersonation_session_for(@user, host:)
  handoff_session.get("/users/#{@user.id}/cross_site_link", params: { site: code })
  @handoff_response = handoff_session.response
end

Then('the switch is refused with {string}') do |message|
  # Sent back here, not to another region, and no hand-off credential minted
  expect(@handoff_response.status).to eq(302)
  expect(@handoff_response.headers["Location"].to_s).not_to include("redirect_to_subdomain")
  # The alert the redirect carries, read off the request that set it
  expect(handoff_session.request.flash[:alert].to_s).to include(message)
end

Then('the signed-in pages show the region selector') do
  handoff_session.get("/users/#{@user.id}/edit")
  expect(handoff_session.response.body).to include("cross_site_link")
end

Then('the signed-in pages show no region selector') do
  handoff_session.get("/users/#{@user.id}/edit")
  # The page rendered (not a redirect to sign-in), and without the region form
  expect(handoff_session.response.status).to eq(200)
  expect(handoff_session.response.body).not_to include("cross_site_link")
end

# ---- L4 -----------------------------------------------------------------------------------------

# The test env runs with forgery protection off (config/environments/test.rb); these scenarios
# switch it on, and put it and the two environment switches back afterwards.
Before("@csrf-protection") do
  @csrf_forgery_was = ActionController::Base.allow_forgery_protection
  @csrf_env_was = ENV.to_h.slice("SKIP_AUTHENTICITY_TOKEN", "VULN_SCAN")
  ActionController::Base.allow_forgery_protection = true
end

After("@csrf-protection") do
  ActionController::Base.allow_forgery_protection = @csrf_forgery_was
  %w[SKIP_AUTHENTICITY_TOKEN VULN_SCAN].each do |key|
    @csrf_env_was&.key?(key) ? ENV[key] = @csrf_env_was[key] : ENV.delete(key)
  end
end

Given('the environment sets SKIP_AUTHENTICITY_TOKEN and VULN_SCAN to {string}') do |value|
  ENV["SKIP_AUTHENTICITY_TOKEN"] = value
  ENV["VULN_SCAN"] = value
end

# The factory user has already accepted the terms, so a refused post would leave accept_terms true
# either way; clear it so "the user has not accepted the terms" can only pass if the post was refused
Given('the user has yet to accept the terms') do
  @user.update_columns(accept_terms: false, accepted_terms_on: nil)
end

When('I accept the terms without a CSRF token') do
  # rack_test posts without the form's authenticity token, as a cross-site form would
  page.driver.submit :post, accept_terms_users_path, {}
end

Then('the user has not accepted the terms') do
  expect(@user.reload.accept_terms).to be_falsey
end

Then('the CSRF boot guard refuses SKIP_AUTHENTICITY_TOKEN in {string} and {string}') do |env_a, env_b|
  switch = { "SKIP_AUTHENTICITY_TOKEN" => "true" }
  [env_a, env_b].each do |rails_env|
    expect { CsrfSwitches.guard!(rails_env:, env: switch) }.to raise_error(RuntimeError, /SKIP_AUTHENTICITY_TOKEN/)
  end
  # Development (the ngrok case) and an unset switch boot normally
  expect { CsrfSwitches.guard!(rails_env: "development", env: switch) }.not_to raise_error
  expect { CsrfSwitches.guard!(rails_env: "production", env: {}) }.not_to raise_error
end

Then('the CSRF skip is honoured only in {string}') do |rails_env|
  switch = { "SKIP_AUTHENTICITY_TOKEN" => "true" }
  expect(CsrfSwitches.skip_verification?(rails_env:, env: switch)).to be(true)
  %w[test staging production].each do |other|
    expect(CsrfSwitches.skip_verification?(rails_env: other, env: switch)).to be(false)
  end
end

# ---- L5 -----------------------------------------------------------------------------------------

Then('the enforced CSP is {string}') do |value|
  expect(page.response_headers["Content-Security-Policy"]).to eq(value)
end

Then('the enforced CSP includes {string}') do |fragment|
  expect(page.response_headers["Content-Security-Policy"].to_s).to include(fragment)
end

Then('the report-only CSP includes {string}') do |fragment|
  expect(page.response_headers["Content-Security-Policy-Report-Only"].to_s).to include(fragment)
end

Then('the Permissions-Policy includes {string}') do |fragment|
  expect(page.response_headers["Permissions-Policy"].to_s).to include(fragment)
end

When('a browser reports a {string} violation on {string}') do |directive, url|
  report = { "csp-report" => { "document-uri" => url, "violated-directive" => directive,
                               "blocked-uri" => "inline", "original-policy" => "script-src 'self'" } }
  # Capture what the controller logs for this one request
  @csp_log_io = StringIO.new
  previous_logger = Rails.logger
  Rails.logger = ActiveSupport::Logger.new(@csp_log_io)
  begin
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.post "/csp_reports", params: report.to_json, headers: { "CONTENT_TYPE" => "application/csp-report" }
    @csp_response = session.response
  ensure
    Rails.logger = previous_logger
  end
end

Then('the CSP report is answered with {int}') do |status|
  expect(@csp_response.status).to eq(status)
end

Then('the CSP log names {string} and {string}') do |directive, page_url|
  line = csp_log.lines.find { |l| l.include?("[csp_report]") }
  expect(line).to be_present, "no [csp_report] line in: #{csp_log}"
  expect(line).to include("directive=#{directive}")
  expect(line).to include("page=#{page_url}")
end

Then('the CSP log does not contain {string}') do |text|
  expect(csp_log).not_to include(text)
end

Given('host checking is on for the base domain {string}') do |domain|
  # The same middleware and matcher config/initializers/security_headers.rb installs when
  # ENFORCE_HOST_AUTHORIZATION=1 (the test app boots with it off), around a stub app
  ok_app = ->(_env) { [200, { "Content-Type" => "text/plain" }, ["ok"]] }
  @host_check = ActionDispatch::HostAuthorization.new(ok_app, [HostAllowlist.new(env: { "BASE_DOMAIN" => domain })],
                                                      exclude: HostAllowlist::EXCLUDE)
end

Given('a tenant has the custom domain {string}') do |domain|
  # update_column: the domain is what a support user maps; no callbacks are needed for the lookup
  FactoryBot.create(:entity, entity_type: "Investment Fund").update_column(:domain, domain)
end

Then('requests answer as follows:') do |table|
  table.hashes.each do |row|
    # HostAuthorization reads the Host header, which env_for does not set from the URL
    env = Rack::MockRequest.env_for(row["path"], "HTTP_HOST" => row["host"])
    status, = @host_check.call(env)
    expect(status).to eq(row["status"].to_i), "#{row['host']}#{row['path']} answered #{status}"
  end
end

When('I open the Outlook task pane') do
  visit "/outlook_addin/taskpane"
end

# ---- L7 -----------------------------------------------------------------------------------------

When('I switch my persona to {string}') do |persona|
  # The persona picker's form, posted as the browser does
  page.driver.submit :post, set_persona_users_path, { user: { persona: } }
end

When('a link opens {string}') do |path|
  visit path
end

Then('my persona is {string}') do |persona|
  expect(@user.reload.curr_role).to eq(persona)
end

# ---- L8 -----------------------------------------------------------------------------------------

Then('the log filter hides the values of:') do |table|
  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  table.hashes.each do |row|
    expect(filter.filter(row["key"] => "sensitive-value")[row["key"]]).to eq("[FILTERED]"), "#{row['key']} was not filtered"
  end
end

Then('the log filter keeps the values of:') do |table|
  filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  table.hashes.each do |row|
    expect(filter.filter(row["key"] => "plain-value")[row["key"]]).to eq("plain-value"), "#{row['key']} was filtered"
  end
end

Then("an investor's inspect hides the PAN {string}") do |pan|
  inspected = Investor.new(investor_name: "Inspect Check", pan:).inspect
  expect(inspected).not_to include(pan)
  expect(inspected).to include("[FILTERED]")
end
