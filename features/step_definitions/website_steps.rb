require 'rack/test'

# Rack::Test client that drives the FULL middleware stack for one request at a
# time with an explicit Host header. Playwright can't assert status codes or
# observe 301s, so — like rack_attack_404_steps.rb — website scenarios talk to
# Rails.application directly.
class WebsiteClient
  include Rack::Test::Methods

  def app
    Rails.application
  end

  # rack-test defaults the host to example.org, so every request states the
  # host it is simulating — that host IS the thing under test here. The host
  # may carry an explicit port (caphive.test:3001) to exercise the
  # port-preserving redirects.
  def request(method, host, path, scheme: 'http')
    send(method, "#{scheme}://#{host}#{path}", {}, { 'HTTP_HOST' => host })
    last_response
  end
end

def website_client
  @website_client ||= WebsiteClient.new
end

When('a visitor requests {string} on host {string}') do |path, host|
  @response = website_client.request(:get, host, path)
end

# Simulates TLS-terminated traffic (the ALB/nginx path): rack-test sets
# rack.url_scheme from the absolute URL, which is what Rack#scheme reads.
When('a visitor requests {string} on host {string} over HTTPS') do |path, host|
  @response = website_client.request(:get, host, path, scheme: 'https')
end

When('a visitor sends a HEAD request for {string} on host {string}') do |path, host|
  @response = website_client.request(:head, host, path)
end

When('a visitor POSTs to {string} on host {string}') do |path, host|
  @response = website_client.request(:post, host, path)
end

Then('the response status is {int}') do |status|
  expect(@response.status).to eq(status),
    "expected HTTP #{status}, got HTTP #{@response.status}"
end

Then('the response redirects to {string}') do |location|
  expect(@response.status).to eq(301),
    "expected a 301 redirect, got HTTP #{@response.status}"
  expect(@response.headers['Location']).to eq(location)
end

# Sign-in redirects from the app are 302s (Devise), asserted separately from
# the website's own 301s so a wrong layer answering is caught.
Then('the response redirects to the sign-in page') do
  expect(@response.status).to eq(302),
    "expected the app's 302 to sign-in, got HTTP #{@response.status}"
  expect(@response.headers['Location']).to include('/users/sign_in')
end

# Rack::Files streams file bodies as BINARY; force UTF-8 so assertions with
# non-ASCII characters (the site uses em dashes in titles) can compare.
Then('the response body contains {string}') do |text|
  expect(@response.body.dup.force_encoding(Encoding::UTF_8)).to include(text)
end

Then('the response body does not contain {string}') do |text|
  expect(@response.body.dup.force_encoding(Encoding::UTF_8)).not_to include(text)
end

Then('the response content type is {string}') do |type|
  expect(@response.headers['Content-Type'].to_s).to start_with(type)
end

# HEAD must have no body (we sit above Rack::Head, so the middleware strips
# it itself) while content-length still advertises the GET body size.
Then('the response has an empty body') do
  expect(@response.body).to be_empty
end
