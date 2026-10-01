# frozen_string_literal: true

# Steps shared by features/login/cross_region_issuance.feature and
# features/login/cross_region_login.feature.
#
# SiteRegistry memoises its parsed settings per process, so every scenario stubs SITES and
# CURRENT_SITE and resets the registry, then restores both afterwards. The inter-region secret
# lives in encrypted credentials, so it is stubbed rather than written to disk.

CROSS_REGION_TEST_SITES = {
  "IN" => "https://app.caphive.test",
  "US" => "https://app.caphive.us.test"
}.freeze

CROSS_REGION_SECRET = "cross-region-test-secret-value-0123456789"

Before("@cross-region-issuance", "@cross-region-login") do
  @cross_region_env = ENV.to_h.slice("SITES", "CURRENT_SITE")
  allow(CrossSiteTrust).to receive(:secret).and_return(CROSS_REGION_SECRET)
end

After("@cross-region-issuance", "@cross-region-login") do
  %w[SITES CURRENT_SITE].each do |key|
    @cross_region_env&.key?(key) ? ENV[key] = @cross_region_env[key] : ENV.delete(key)
  end
  SiteRegistry.reset!
end

def set_cross_region_sites(codes)
  ENV["SITES"] = codes.index_with { |c| CROSS_REGION_TEST_SITES.fetch(c) }.to_json
  SiteRegistry.reset!
end

Given("the regions are {string}") do |csv|
  set_cross_region_sites(csv.split(",").map(&:strip))
  ENV["CURRENT_SITE"] ||= csv.split(",").first.strip
  SiteRegistry.reset!
end

Given("the current region is {string}") do |code|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
end

Given("a user {string} whose stored regions are {string}") do |email, regions|
  @entity ||= FactoryBot.create(:entity, first_name: "Silicon Road", entity_type: "Investment Fund")
  # update_column, so the deliberately malformed values in these scenarios survive any
  # normalising callback - they are exactly the shapes found in production data.
  @user = FactoryBot.create(:user, email: email, entity: @entity, primary_region: "IN")
  @user.update_column(:regions, regions)
  @user.reload
end

Then("that user's switchable regions should be {string}") do |csv|
  expect(@user.switchable_region_codes).to eq(csv.split(",").map(&:strip))
end

Then("that user's stored regions should still be {string}") do |value|
  expect(@user.reload.regions).to eq(value)
end

# The selector renders exactly when there is more than one region to switch between - the view
# itself has no other condition, which is the point of moving the logic onto the model.
Then("the region selector should be shown for that user") do
  expect(@user.switchable_region_codes.many?).to be(true)
end

Then("the region selector should not be shown for that user") do
  expect(@user.switchable_region_codes.many?).to be(false)
end

Then("that user should not be permitted to switch to {string}") do |code|
  expect(UserPolicy.new(@user, @user).cross_site_link?(site: code)).to be(false)
end

Then("that user should be permitted to switch to {string}") do |code|
  expect(UserPolicy.new(@user, @user).cross_site_link?(site: code)).to be(true)
end

When("a hand-off credential is minted for that user targeting {string}") do |code|
  @mint_error = nil
  @credential = nil
  begin
    @credential = CrossSiteLink.new.generate(@user.email, purpose: CrossSiteLink::PURPOSE,
                                                          site: code, from: SiteRegistry.current_code)
  rescue ArgumentError => e
    @mint_error = e
  end
end

Then("minting should be refused") do
  expect(@mint_error).to be_a(ArgumentError), "expected minting to be refused, got a credential"
  expect(@credential).to be_nil
end

Then("the credential should verify successfully") do
  @verify_result = CrossSiteLink.new.verify(@credential, purpose: CrossSiteLink::PURPOSE,
                                                         site: SiteRegistry.current_code)
  expect(@verify_result.ok?).to be(true), "expected the credential to verify, got #{@verify_result.reason.inspect}"
end

Then("the credential should carry origin region {string}") do |code|
  expect(@verify_result.origin_code.to_s).to eq(code)
end

# Only "+" matters: a query parser turns it into a space, which would corrupt the signature.
# "/" and "=" ride through a query VALUE untouched.
Then("the credential should contain no plus character") do
  expect(@credential).not_to include("+")
end

Then("the credential should survive query string parsing unchanged") do
  expect(Rack::Utils.parse_nested_query("token=#{@credential}")["token"]).to eq(@credential)
end
