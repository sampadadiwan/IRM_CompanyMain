# frozen_string_literal: true

Given(/^the user's entity has sub_domain "([^"]+)"$/) do |sub|
  @user.entity.update!(sub_domain: sub)
  @sub_domain = sub
end

Given(/^the user's entity has no sub_domain$/) do
  # update_column bypasses the before_save that auto-generates sub_domain
  @user.entity.update_column(:sub_domain, nil)
  @sub_domain = nil
end

Given(/^a cross-site login token is generated for "([^"]+)" targeting site "([^"]+)"$/) do |email, site|
  # `from` is required now: the hand-off carries where it came from so a failure can offer a
  # way back. Any deployed region other than the destination will do here.
  origin = (SiteRegistry.codes - [SiteRegistry.normalize(site)]).first || SiteRegistry.current_code
  @cross_site_token = CrossSiteLink.new.generate(email, purpose: CrossSiteLink::PURPOSE,
                                                        site: site, from: origin)
end

When(/^I request redirect_to_subdomain on host "([^"]+)"$/) do |host|
  header "Host", host
  @request_host = host
  get "/users/redirect_to_subdomain?token=#{@cross_site_token}"
  @last_response = last_response
end

When(/^I request redirect_to_subdomain with invalid token on host "([^"]+)"$/) do |host|
  header "Host", host
  get "/users/redirect_to_subdomain?token=badtoken"
  @last_response = last_response
end

# Asserts a 302 to {sub_domain}.{domain}/users/cross_site_login?token=...
# where domain is derived by stripping the first label off the request host.
Then(/^I should be redirected to "([^"]+)" for cross-site login$/) do |expected_host|
  expect(@last_response.status).to eq(302)
  uri = URI(@last_response.headers["Location"])
  expect(uri.host).to eq(expected_host)
  expect(uri.path).to eq("/users/cross_site_login")
  # Query values are escaped and ordered by to_query now, so assert on the parsed params
  # rather than on a literal prefix.
  expect(Rack::Utils.parse_nested_query(uri.query)["token"]).to be_present
end

Given(/^site "([^"]+)" is served at "([^"]+)"$/) do |site, base_url|
  @site_map ||= {}
  @site_map[site] = base_url
  # ENV["SITES"] is JSON now, parsed by SiteRegistry. It used to be a Ruby hash literal that
  # the controller ran through `eval` at request time.
  ENV["SITES"] = @site_map.to_json
  SiteRegistry.reset!
end

# Uses a dedicated integration session (rather than the bare Rack::Test DSL used
# elsewhere in this file) so the Devise session cookie from sign-in is preserved
# across the authenticated cross_site_link request that follows.
Given(/^I am signed in as "([^"]+)" on host "([^"]+)"$/) do |email, host|
  @cross_site_session = ActionDispatch::Integration::Session.new(Rails.application)
  @cross_site_session.host = host
  @cross_site_session.post "/users/sign_in", params: { user: { email: email, password: "password" } }
end

When(/^I click the cross-site link targeting site "([^"]+)"$/) do |site|
  @cross_site_session.get "/users/#{@user.id}/cross_site_link", params: { site: site }
  @last_response = @cross_site_session.response
end

# The origin region the hand-off is minted FROM. Previously implicit in whatever CURRENT_SITE
# happened to be, which made the one end-to-end scenario a degenerate self-switch.
Given(/^the current site is "([^"]+)"$/) do |code|
  ENV["CURRENT_SITE"] = code
  SiteRegistry.reset!
end

Then(/^I should land on the sign-in screen with a cross-region banner$/) do
  expect(@last_response.status).to eq(302)
  expect(URI(@last_response.headers["Location"]).path).to eq("/users/sign_in")
end

Then(/^I should be redirected to "([^"]+)" to resolve the subdomain$/) do |expected_host|
  expect(@last_response.status).to eq(302)
  uri = URI(@last_response.headers["Location"])
  expect(uri.host).to eq(expected_host)
  expect(uri.path).to eq("/users/redirect_to_subdomain")
  params = Rack::Utils.parse_nested_query(uri.query)
  expect(params["token"]).to be_present
  expect(params["from"]).to be_present
end

When(/^I follow that redirect$/) do
  location = URI(@last_response.headers["Location"])
  header "Host", location.host
  get location.request_uri
  @last_response = last_response
end

# Sets CURRENT_SITE to simulate this request landing on the target instance,
# since cross_site_login checks the token's embedded site against ENV["CURRENT_SITE"].
When(/^I follow that redirect as site "([^"]+)"$/) do |current_site|
  ENV["CURRENT_SITE"] = current_site
  # SiteRegistry memoises the active region, so swapping the env var is not enough to make the
  # next hop believe it is running on the other region.
  SiteRegistry.reset!
  location = URI(@last_response.headers["Location"])
  header "Host", location.host
  get location.request_uri
  @last_response = last_response
end

Then(/^I should be signed in and redirected to the site root$/) do
  expect(@last_response.status).to eq(302)
  expect(URI(@last_response.headers["Location"]).path).to eq("/")
  # Follow through: if sign_in hadn't actually taken effect this would bounce to /users/sign_in
  follow_redirect!
  expect(last_response).not_to be_redirect
end
