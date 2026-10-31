# frozen_string_literal: true

# Steps for the 2026-10 security review findings H12 (Gmail add-in sign-in) and H13 (web 2FA
# attempt counting). Design and worked examples: docs/security/security_review_2026_10.md, cards
# "H12 — Gmail add-in sign-in" and "H13 — Web 2FA attempt counting".
#
# Both drive plain HTTP sessions rather than a browser: H12's callback points at
# script.google.com, which a browser would try to load, and H13-1 has to save and restore the
# session cookie byte for byte, which is what an attacker replaying it does.
#
# Reused from elsewhere: "there is a user ... for an entity ..." (user + entity), the 2FA setup
# and form steps (two_factor_steps.rb, login.rb), the MCP client steps (mcp_transport_steps.rb)
# and the Rack::Attack visitor steps (rack_attack_404_steps.rb).

# ── H12 helpers ─────────────────────────────────────────────────────────────

module SecurityH12Helpers
  # The callback the published add-on sends (addons/gmail/Code.gs getCallbackUrl + state)
  def h12_callback(script_id)
    "https://script.google.com/macros/d/#{script_id}/usercallback?state=#{@h12_state ||= "state-#{SecureRandom.hex(8)}"}"
  end

  # Tokens minted for the mail add-ins — the thing H12 must not hand out on a GET
  def h12_mail_tokens
    Doorkeeper::AccessToken.where(application_id: MailAddinToken.application_scope.select(:id))
  end

  # A signed-in session for @user, as the browser tab the add-on opens would have
  def h12_session
    @h12_session ||= ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
      expect(session.response.status).to eq(302), "sign-in failed: HTTP #{session.response.status}"
    end
  end
end
World(SecurityH12Helpers)

# H12 — the per-environment allowlist lives in credentials (gmail_addin.script_ids). Stubbed for
# the scenario rather than written to a credentials file; every other credentials lookup still
# reads the real file.
Given("the Gmail add-on script ids for this environment are {string}") do |ids|
  allow(Rails.application.credentials).to receive(:dig).and_call_original
  allow(Rails.application.credentials).to receive(:dig).with(:gmail_addin, :script_ids).and_return(ids.split(","))
end

When("I open the Gmail add-on sign-in for script {string} with a state token") do |script_id|
  h12_session.get "/gmail_addin/oauth_start", params: { redirect_uri: h12_callback(script_id) }
end

When("I open the Gmail add-on sign-in with the callback {string}") do |callback|
  h12_session.get "/gmail_addin/oauth_start", params: { redirect_uri: callback }
end

# What a crafted form on another site would submit if it could get past CSRF — proves the POST
# re-checks the callback rather than trusting the confirm page to have done it
When("I post the Gmail add-on confirmation for script {string}") do |script_id|
  h12_session.post "/gmail_addin/oauth_start", params: { redirect_uri: h12_callback(script_id) }
end

When("I confirm the Gmail add-on connection") do
  # Submits the confirm page's own form: its hidden redirect_uri is what the button posts
  hidden = Nokogiri::HTML(h12_session.response.body).at_css("#gmail_addin_confirm_page input[name='redirect_uri']")
  expect(hidden).to be_present, "the confirm page has no redirect_uri field"
  h12_session.post "/gmail_addin/oauth_start", params: { redirect_uri: hidden["value"] }
end

Then("I should see the Gmail add-on confirm page for the user") do
  expect(h12_session.response.status).to eq(200), "got #{h12_session.response.status}: #{h12_session.response.body.first(200)}"
  page_html = Nokogiri::HTML(h12_session.response.body)
  expect(page_html.text).to include("Connect CapHive Filing (Gmail)")
  expect(page_html.text).to include(@user.email)
  expect(page_html.at_css("button#gmail_addin_confirm")).to be_present
end

Then("the Gmail add-on sign-in should be refused with {int}") do |status|
  expect(h12_session.response.status).to eq(status)
  expect(h12_session.response.body).to include("Invalid sign-in callback address.")
end

Then("no mail add-in token should have been issued") do
  expect(h12_mail_tokens.count).to eq(0)
end

Then("I should be redirected to the Gmail add-on callback for script {string} with a token") do |script_id|
  expect(h12_session.response.status).to eq(302)
  location = URI.parse(h12_session.response.location)
  # Back to exactly the add-on's own callback, with its state token intact
  expect("#{location.scheme}://#{location.host}#{location.path}").to eq("https://script.google.com/macros/d/#{script_id}/usercallback")
  @h12_callback_params = Rack::Utils.parse_query(location.query)
  expect(@h12_callback_params["state"]).to eq(@h12_state)
  expect(@h12_callback_params["token"]).to be_present
end

Then("the token in the callback should be a mail add-in token for the user") do
  token = Doorkeeper::AccessToken.by_token(@h12_callback_params["token"])
  expect(token).to be_present
  expect(MailAddinToken.issued?(token)).to be(true)
  expect(token.resource_owner_id).to eq(@user.id)
end

# H12-X — the MCP client steps post with @mcp_token; here it is a mail add-in token instead
Given("the user's MCP access token is a mail add-in token") do
  @mcp_token = MailAddinToken.issue_for(@user).plaintext_token
end

# ── H13 helpers ─────────────────────────────────────────────────────────────

# One browser's worth of cookies driving the website sign-in, so a scenario can save and restore
# the session cookie the way an attacker replaying it would.
class SecurityH13Browser
  include Rack::Test::Methods

  def app
    Rails.application
  end

  # The password step; for a 2FA user this starts a challenge and redirects to the code screen
  def enter_password(user)
    post "/users/sign_in", user: { email: user.email, password: "password" }
    last_response
  end

  # One code typed on the login code screen
  def enter_code(code)
    post "/two_factor", otp_code: code
    last_response
  end

  # The whole cookie jar, copied so later responses cannot change the saved one
  def saved_cookies
    current_session.cookie_jar.dup
  end

  def restore_cookies(jar)
    current_session.cookie_jar = jar.dup
  end

  # Where the last response sent the browser, without the host
  def redirected_to
    last_response.redirect? ? URI.parse(last_response.location).path : nil
  end
end

module SecurityH13Helpers
  def h13_browser
    @h13_browser ||= SecurityH13Browser.new
  end

  # The redirect back to sign-in, followed, so the flash it carries can be read
  def h13_expect_back_at_sign_in_with(text)
    expect(h13_browser.redirected_to).to eq("/users/sign_in"),
                                         "expected a redirect to sign-in, got HTTP #{h13_browser.last_response.status} " \
                                         "#{h13_browser.last_response.location.inspect}"
    h13_browser.follow_redirect!
    expect(h13_browser.last_response.body).to include(text)
  end
end
World(SecurityH13Helpers)

Given("the user has entered their password on the website") do
  h13_browser.enter_password(@user)
  expect(h13_browser.redirected_to).to eq("/two_factor/new")
end

Given("the browser cookie is saved") do
  @h13_saved_cookies = h13_browser.saved_cookies
end

When("the saved cookie is restored") do
  h13_browser.restore_cookies(@h13_saved_cookies)
end

When("the user enters {int} wrong codes") do |count|
  count.times { h13_browser.enter_code("000000") }
end

When("the user enters the right code") do
  h13_browser.enter_code(@user.reload.current_otp)
end

Then("the user should be sent back to sign in with {string}") do |text|
  h13_expect_back_at_sign_in_with(text)
end

Then("the replaying browser should not be signed in") do
  h13_browser.get "/entities/dashboard"
  expect(h13_browser.redirected_to).to eq("/users/sign_in")
end

# H13-2 — keeps going like a guesser would: a fresh password login after each spent challenge,
# up to 3 codes each, stopping a login early once the server sends the browser back to sign-in.
When("the user tries {int} wrong codes on each of {int} password logins") do |codes, logins|
  @h13_codes_entered = 0
  logins.times do
    # A refused password (the account is locked) ends the attempt — there is no code screen
    h13_browser.enter_password(@user)
    break unless h13_browser.redirected_to == "/two_factor/new"

    codes.times do
      h13_browser.enter_code("000000")
      @h13_codes_entered += 1
      # Sent back to sign-in: this challenge is over (or the account just locked)
      break if h13_browser.redirected_to == "/users/sign_in"
    end
  end
end

Then("the account should be locked at the {int}th wrong code") do |count|
  expect(@h13_codes_entered).to eq(count)
  expect(@user.reload.access_locked?).to be(true)
  h13_expect_back_at_sign_in_with("Your account has been locked after too many incorrect codes")
end

# Cucumber runs ActiveJob inline, so the deliver_later unlock mail is already in deliveries
Then("the user should have received an unlock email") do
  mail = ActionMailer::Base.deliveries.find { |m| m.to.include?(@user.email) && m.subject == "Unlock instructions" }
  expect(mail).to be_present
end

Then("a password login should be refused") do
  h13_browser.enter_password(@user)
  expect(h13_browser.redirected_to).not_to eq("/two_factor/new")
end

# H13-3 — reuses RackAttackClient (rack_attack_404_steps.rb), which sends X-Forwarded-For so the
# requests come from a real client IP rather than the safelisted loopback
When("{string} posts {int} two-factor codes") do |name, count|
  client = @rack_clients[name]
  # Rack::Attack counts in fixed 60-second windows; freezing the clock keeps every post in one
  # window, so the scenario cannot straddle a minute boundary and flake (the @rack_attack hook
  # travels back afterwards)
  freeze_time
  @h13_code_statuses = Array.new(count) do
    client.post("/two_factor", { otp_code: "000000" }, { "HTTP_X_FORWARDED_FOR" => client.ip })
    client.last_response.status
  end
end

Then("the first {int} code posts should reach the app and the next be throttled") do |allowed|
  expect(@h13_code_statuses.first(allowed)).not_to include(429)
  # Compare whole arrays: Capybara's `all` finder shadows RSpec's `all` matcher in the World
  rest = @h13_code_statuses.drop(allowed)
  expect(rest).not_to be_empty
  expect(rest).to eq(Array.new(rest.size, 429))
end
