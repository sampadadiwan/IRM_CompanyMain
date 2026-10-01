# frozen_string_literal: true

# Steps for features/login/cross_region_trust.feature.
#
# The inter-region secret lives in encrypted credentials, so scenarios stub CrossSiteTrust.secret
# rather than writing credentials files. SITES is pointed at hosts that do not exist so the peer
# fetch is always served by WebMock and never by the Capybara server.

Before("@cross-region-trust") do
  @trust_env = ENV.to_h.slice("SITES", "CURRENT_SITE")
  ENV["SITES"] = %({"IN":"https://app.test-in.example","US":"https://app.test-us.example"})
  ENV["CURRENT_SITE"] = "IN"
  SiteRegistry.reset!
  @trust_fingerprints = {}
end

After("@cross-region-trust") do
  %w[SITES CURRENT_SITE].each do |key|
    @trust_env&.key?(key) ? ENV[key] = @trust_env[key] : ENV.delete(key)
  end
  SiteRegistry.reset!
end

def fingerprint_for(secret)
  OpenSSL::HMAC.hexdigest("SHA256", secret, CrossSiteTrust::PROBE)
end

Given("region {string} is configured with inter-region secret {string}") do |code, secret|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
  allow(CrossSiteTrust).to receive(:secret).and_return(secret)
end

Given("region {string} is configured with no inter-region secret") do |code|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
  allow(CrossSiteTrust).to receive(:secret).and_return(nil)
end

Given("I capture the trust fingerprint as {string}") do |label|
  @trust_fingerprints[label] = CrossSiteTrust.fingerprint
end

Then("the captured fingerprints {string} and {string} should match") do |a, b|
  expect(@trust_fingerprints[a]).to be_present
  expect(@trust_fingerprints[a]).to eq(@trust_fingerprints[b])
end

Then("the captured fingerprints {string} and {string} should not match") do |a, b|
  expect(@trust_fingerprints[a]).to be_present
  expect(@trust_fingerprints[b]).to be_present
  expect(@trust_fingerprints[a]).not_to eq(@trust_fingerprints[b])
end

When("I request the cross-site trust endpoint") do
  get "/health_check/cross_site_trust"
  @trust_response = last_response
  @trust_body = JSON.parse(last_response.body)
end

Then("the trust response should report the region as {string}") do |code|
  expect(@trust_response.status).to eq(200)
  expect(@trust_body["region"]).to eq(code)
end

Then("the trust response should report the secret as configured") do
  expect(@trust_body["configured"]).to be(true)
end

Then("the trust response should report the secret as not configured") do
  expect(@trust_response.status).to eq(200), "a configuration report must not fail the health check"
  expect(@trust_body["configured"]).to be(false)
end

Then("the trust response fingerprint should be {int} hex characters") do |length|
  expect(@trust_body["fingerprint"]).to match(/\A[0-9a-f]{#{length}}\z/)
end

Then("the trust response fingerprint should be empty") do
  expect(@trust_body["fingerprint"]).to be_nil
end

Then("the trust response should not contain {string}") do |secret|
  expect(@trust_response.body).not_to include(secret)
end

Given("peer region {string} reports fingerprint for secret {string}") do |code, secret|
  WebMock::API.stub_request(:get, "#{SiteRegistry.url_for(code)}/health_check/cross_site_trust")
    .to_return(status: 200,
               body: { region: code, configured: true, fingerprint: fingerprint_for(secret) }.to_json,
               headers: { "Content-Type" => "application/json" })
end

Given("peer region {string} reports that it has no secret configured") do |code|
  WebMock::API.stub_request(:get, "#{SiteRegistry.url_for(code)}/health_check/cross_site_trust")
    .to_return(status: 200,
               body: { region: code, configured: false, fingerprint: nil }.to_json,
               headers: { "Content-Type" => "application/json" })
end

Given("peer region {string} is unreachable") do |code|
  WebMock::API.stub_request(:get, "#{SiteRegistry.url_for(code)}/health_check/cross_site_trust")
    .to_raise(Errno::ECONNREFUSED)
end

Given("a peer secret mismatch has previously been recorded as {string}") do |value|
  CrossSiteTrust.record_mismatch(value == "true")
end

When("the cross-site trust check runs") do
  CrossSiteTrustCheckJob.new.perform
end

Then("a peer secret mismatch should be recorded") do
  expect(CrossSiteTrust.peer_mismatch?).to be(true)
end

Then("no peer secret mismatch should be recorded") do
  expect(CrossSiteTrust.peer_mismatch?).to be(false)
end
