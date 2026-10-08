# frozen_string_literal: true

# Steps for features/login/cross_region_login.feature - the hand-off driven over real HTTP.
#
# The suite emulates a two-region deployment in one process: both regions resolve to the same
# Capybara app, and a scenario "moves" between them by swapping CURRENT_SITE and sending the
# next request with the destination's Host header. That proves the routing, the credential and
# the subdomain logic end to end; what it cannot prove is that two separately deployed
# databases agree on the user, which is the same limitation the pre-existing
# @cross-site-login-flow scenario carries.

World(ActiveSupport::Testing::TimeHelpers)

# Captures what the app logs during a scenario, so the "no credential in any log line" and
# "the reason and the user are logged" assertions have something to read.
Before("@cross-region-login") do
  @cross_region_log = StringIO.new
  @cross_region_previous_logger = Rails.logger
  Rails.logger = ActiveSupport::Logger.new(@cross_region_log)
end

After("@cross-region-login") do
  Rails.logger = @cross_region_previous_logger if @cross_region_previous_logger
  travel_back
end

def handoff_session
  @handoff_session ||= ActionDispatch::Integration::Session.new(Rails.application)
end

# Re-issues a redirect's Location against the test app, carrying its Host across - which is how
# one process stands in for two regions.
def follow_handoff_redirect(location)
  capture_handoff_params(location)
  uri = URI(location)
  handoff_session.host = uri.host
  handoff_session.get("#{uri.path}?#{uri.query}")
  # ActionDispatch::Integration::Session#get returns the status integer, not the response.
  handoff_session.response
end

def last_location
  @handoff_response.headers["Location"]
end

# Every hop carries the credential forward in its query, so capture it wherever it appears
# rather than only in the step that asserts the first redirect - otherwise a scenario that
# skips that assertion silently presents no credential at all later on.
def capture_handoff_params(location)
  query = URI(location.to_s).query
  return if query.blank?

  params = Rack::Utils.parse_nested_query(query)
  @credential = params["token"] if params["token"].present?
  @handoff_from = params["from"] if params["from"].present?
end

Given("the user's company site in the destination region is {string}") do |sub|
  @user.entity.update!(sub_domain: sub)
end

Given("the user's company has no site in the destination region") do
  # update_column bypasses the callback that regenerates sub_domain.
  @user.entity.update_column(:sub_domain, nil)
end

When("that user starts a switch to {string}") do |code|
  handoff_session.host = URI(SiteRegistry.url_for(SiteRegistry.current_code)).host
  handoff_session.post("/users/sign_in", params: { user: { email: @user.email, password: "password" } })
  handoff_session.get("/users/#{@user.id}/cross_site_link", params: { site: code })
  @handoff_response = handoff_session.response
end

Then("the browser should be sent to the {string} region to resolve the subdomain") do |code|
  expect(@handoff_response.status).to eq(302), "got #{@handoff_response.status}: #{@handoff_response.body[0, 300]}"
  expect(last_location).to start_with("#{SiteRegistry.url_for(code)}/users/redirect_to_subdomain?")
  capture_handoff_params(last_location)
  expect(@credential).to be_present
  expect(@handoff_from).to be_present
end

When("the destination region is {string} and the browser follows that redirect") do |code|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
  @handoff_response = follow_handoff_redirect(last_location)
end

Then("the browser should be sent to host {string} to sign in") do |host|
  expect(@handoff_response.status).to eq(302), "got #{@handoff_response.status}"
  uri = URI(last_location)
  expect(uri.host).to eq(host)
  expect(uri.path).to eq("/users/cross_site_login")
  expect(Rack::Utils.parse_nested_query(uri.query)["token"]).to eq(@credential)
end

When("the browser follows that redirect") do
  @handoff_response = follow_handoff_redirect(last_location)
end

Then("the user should be signed in on the destination region") do
  expect(@handoff_response.status).to eq(302), "got #{@handoff_response.status}: #{@handoff_response.body[0, 300]}"
  expect(URI(last_location).path).to eq("/")
  # Prove the session really took: an unauthenticated follow-through would bounce to sign-in.
  handoff_session.get("/users/#{@user.id}/edit")
  expect(handoff_session.response.status).not_to eq(401)
  expect(URI(handoff_session.response.headers["Location"].to_s).path).not_to eq("/users/sign_in")
end

Then("the user should not be signed in") do
  expect(URI(last_location.to_s).path).to eq("/users/sign_in")
end

# ---- Presenting a credential directly at the sign-in hop ----

def present_credential(token, host: nil)
  handoff_session.host = host || URI(SiteRegistry.url_for(SiteRegistry.current_code)).host
  # MessageVerifier stamps an ABSOLUTE expiry using the ISSUING box's clock and compares it
  # against the VERIFYING box's, so skew between the regions subtracts directly from the
  # credential's lifetime. Moving this process's clock forward is exactly that asymmetry.
  travelling(@destination_clock_skew) do
    handoff_session.get("/users/cross_site_login", params: { token: token, from: @handoff_from }.compact)
  end
  @handoff_response = handoff_session.response
end

def travelling(skew)
  return yield if skew.nil?

  travel_to(Time.now + skew) { yield }
end

Given("a hand-off credential that expired {int} minutes ago") do |minutes|
  @handoff_from = SiteRegistry.current_code
  travel_to(minutes.minutes.ago) do
    @credential = CrossSiteLink.new.generate(@user.email, purpose: CrossSiteLink::PURPOSE,
                                                          site: "US", from: @handoff_from)
  end
end

Given("a hand-off credential minted with purpose {string} targeting {string}") do |purpose, code|
  @handoff_from = SiteRegistry.current_code
  @credential = CrossSiteLink.new.generate(@user.email, purpose: purpose.to_sym,
                                                        site: code, from: @handoff_from)
end

Given("a hand-off credential for {string} targeting {string}") do |email, code|
  @handoff_from = SiteRegistry.current_code
  @credential = CrossSiteLink.new.generate(email, purpose: CrossSiteLink::PURPOSE,
                                                  site: code, from: @handoff_from)
end

When("the credential is tampered with") do
  @credential = "#{@credential[0..-3]}zz"
end

Given("the hourly trust check has found the regions' secrets differ") do
  CrossSiteTrust.record_mismatch(true)
end

When("the destination region is {string} and that credential is presented for sign-in") do |code|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
  present_credential(@credential)
end

When("the sign-in hop is requested with no credential") do
  present_credential(nil)
end

# A fresh integration session, i.e. a different browser. That is the case the single-use
# guarantee exists for - a credential recovered from history, a proxy log or a shared screen
# and redeemed by someone who is NOT already signed in. (Replaying it in the original browser
# bounces to the app instead, because Devise sends an already-signed-in visitor away from the
# sign-in screen; nothing is granted either way.)
When("that same credential is presented for sign-in again from a different browser") do
  @handoff_session = nil
  @sign_in_body = nil
  present_credential(@credential)
end

# ---- Banner assertions ----

def sign_in_page_body
  @sign_in_body ||= begin
    follow_handoff_redirect(last_location)
    handoff_session.response.body
  end
end

Then("the sign-in screen should show the {string} cross-region banner") do |reason|
  expect(URI(last_location.to_s).path).to eq("/users/sign_in")
  expect(sign_in_page_body).to include('id="flash_cross_region"')
  expect(sign_in_page_body).to include(%(data-reason="#{reason}"))
end

Then("the banner should offer a way back to {string}") do |code|
  expect(sign_in_page_body).to include(SiteRegistry.url_for(code))
end

Then("the banner should offer no way back") do
  SiteRegistry.codes.each do |code|
    next if code == SiteRegistry.current_code

    expect(sign_in_page_body).not_to include(SiteRegistry.url_for(code))
  end
end

# ---- Nonce / concurrency ----

Then("the credential should still be unclaimed") do
  expect(Rails.cache.read(CrossSiteLink::Nonce.key_for(@credential))).to be_nil
end

When("the credential is claimed once") do
  expect(CrossSiteLink::Nonce.claim(@credential)).to be(true)
end

When("the credential is claimed by {int} threads at once") do |count|
  gate = Queue.new
  @claim_results = Array.new(count)
  threads = count.times.map do |i|
    Thread.new do
      gate.pop
      @claim_results[i] = CrossSiteLink::Nonce.claim(@credential)
    end
  end
  count.times { gate << :go }
  threads.each(&:join)
end

Then("exactly one claim should have won") do
  expect(@claim_results.count(true)).to eq(1), "claims: #{@claim_results.inspect}"
end

# The claim lives in the region's shared cache, not in process memory, so a fresh caller sees it.
Then("a claim from another app server should be refused") do
  expect(CrossSiteLink::Nonce.claim(@credential)).to be(false)
end

# ---- Clock drift ----

Given("the destination region's clock is {int} minutes ahead") do |minutes|
  @destination_clock_skew = minutes.minutes
end

# ---- Leak assertions ----

Then("the page should not contain the credential") do
  expect(sign_in_page_body).not_to include(@credential)
end

Then("the page should not contain a server hostname") do
  expect(sign_in_page_body).not_to include(Socket.gethostname)
end

Then("the page should not name an internal error class") do
  %w[CrossSiteLink CrossSiteRejection MessageVerifier InvalidSignature SiteRegistry]
    .each { |name| expect(sign_in_page_body).not_to include(name) }
end

Then("the captured log should not contain the credential") do
  expect(@cross_region_log.string).not_to include(@credential)
end

Then("the captured log should name the reason and the user") do
  expect(@cross_region_log.string).to include("cross_region_handoff rejected")
  expect(@cross_region_log.string).to include("reason=expired")
end

Then("the hand-off success should be logged with both regions") do
  expect(@cross_region_log.string).to include("cross_region_handoff ok")
  expect(@cross_region_log.string).to include("from=IN")
  expect(@cross_region_log.string).to include("to=US")
end

Then("the rejection logged should be {string}") do |reason|
  expect(@cross_region_log.string).to include("reason=#{reason}")
end

# The secret lives in encrypted credentials; a region deployed without it can neither sign nor
# verify, and used to raise ArgumentError out of CrossSiteLink.new into a 500 - the one failure
# the rejection presenter could not reach.
Given("this region has no inter-region secret configured") do
  allow(CrossSiteTrust).to receive(:secret).and_return(nil)
  allow(CrossSiteTrust).to receive(:configured?).and_return(false)
end
