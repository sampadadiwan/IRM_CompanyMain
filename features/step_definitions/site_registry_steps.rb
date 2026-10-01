# frozen_string_literal: true

# Steps for features/misc/site_registry.feature.
#
# SiteRegistry memoises its parsed settings per process, so every scenario here must stub ENV
# and call reset!, then restore both on the way out - otherwise the first scenario's stub leaks
# into every later scenario in the run, including unrelated features.

Before("@site-registry") do
  @site_registry_env = ENV.to_h.slice("SITES", "CURRENT_SITE")
end

After("@site-registry") do
  %w[SITES CURRENT_SITE].each do |key|
    if @site_registry_env&.key?(key)
      ENV[key] = @site_registry_env[key]
    else
      ENV.delete(key)
    end
  end
  SiteRegistry.reset!
end

Given("the region list is set to {string}") do |value|
  ENV["SITES"] = value
  SiteRegistry.reset!
end

Given("the active region is set to {string}") do |value|
  ENV["CURRENT_SITE"] = value
  SiteRegistry.reset!
end

Given("the active region is unset") do
  ENV.delete("CURRENT_SITE")
  SiteRegistry.reset!
end

When("the site registry is validated") do
  @site_registry_error = nil
  begin
    SiteRegistry.validate!
  rescue SiteRegistry::ConfigurationError => e
    @site_registry_error = e
  end
end

Then("validation should succeed") do
  expect(@site_registry_error).to be_nil,
                                  "expected validation to pass, got: #{@site_registry_error&.message}"
end

Then("validation should fail naming {string}") do |setting|
  expect(@site_registry_error).to be_a(SiteRegistry::ConfigurationError),
                                  "expected validation to fail, but it passed"
  expect(@site_registry_error.message).to include(setting)
end

Then("the validation message should mention {string}") do |fragment|
  expect(@site_registry_error&.message.to_s).to include(fragment)
end

Then("the active region code should be {string}") do |code|
  expect(SiteRegistry.current_code).to eq(code)
end

Then("the registry should know the region {string}") do |code|
  expect(SiteRegistry.known?(code)).to be(true)
end

Then("the registry should not know the region {string}") do |code|
  expect(SiteRegistry.known?(code)).to be(false)
end

Then("the base URL for region {string} should be {string}") do |code, url|
  expect(SiteRegistry.url_for(code)).to eq(url)
end

Then("the peer regions should be {string}") do |codes|
  expect(SiteRegistry.peers).to eq(codes.split(",").map(&:strip))
end
