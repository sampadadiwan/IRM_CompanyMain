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
  @cross_site_token = CrossSiteLink.new.generate(email, purpose: :login, site: site.to_sym, expires_in: 30.seconds)
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
  location = @last_response.headers["Location"]
  expect(location).to start_with("http://#{expected_host}/users/cross_site_login?token=")
end

Given(/^site "([^"]+)" is served at "([^"]+)"$/) do |site, base_url|
  @site_map ||= {}
  @site_map[site] = base_url
  # ENV["SITES"] is a stringified ruby hash literal, eval'd by the controller -
  # quoted keys like 'US': become symbol keys (:US), matching params[:site].to_sym
  ENV["SITES"] = "{#{@site_map.map { |site_key, url| "'#{site_key}': '#{url}'" }.join(', ')}}"
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

Then(/^I should be redirected to "([^"]+)" to resolve the subdomain$/) do |expected_host|
  expect(@last_response.status).to eq(302)
  expect(@last_response.headers["Location"]).to start_with("http://#{expected_host}/users/redirect_to_subdomain?token=")
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
