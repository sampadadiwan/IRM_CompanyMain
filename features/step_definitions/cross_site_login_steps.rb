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
