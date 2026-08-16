# frozen_string_literal: true

require 'rack/test'

# Step definitions for features/core/website_leads.feature.
#
# These drive Rack::Test against the FULL middleware stack rather than Capybara,
# for three reasons the browser cannot give us:
#
#   * the endpoint is cross-origin, so the Origin header is the thing under test;
#   * the client posts multipart/form-data, and a JSON-only endpoint would fail
#     silently against every real submission — so the body is built as real
#     multipart, not as Rack::Test's default urlencoded params;
#   * the throttle scenario needs X-Forwarded-For, because 127.0.0.1 is
#     deliberately safelisted in config/initializers/rack_attack.rb.
class WebsiteLeadClient
  include Rack::Test::Methods

  # Fixed boundary, written by hand rather than taken from rack-test. The
  # multipart body is built here on purpose: rack-test only encodes multipart
  # when a param is an UploadedFile, and its internal helpers are private and
  # have changed shape across 1.x/2.x. The whole point of this test is that the
  # endpoint accepts what a real browser FormData post sends, so the bytes on the
  # wire should be visible in the test rather than delegated.
  BOUNDARY = "----CucumberWebsiteLeadBoundary"

  def app
    Rails.application
  end

  # Posts exactly what the website's fetch() posts: multipart/form-data with an
  # Accept header, no cookies, and an Origin.
  def submit(fields, origin: nil, ip: nil)
    body = build_multipart(fields)
    env = {
      'CONTENT_TYPE' => "multipart/form-data; boundary=#{BOUNDARY}",
      'HTTP_ACCEPT' => 'application/json'
    }
    env['HTTP_ORIGIN'] = origin if origin
    env['HTTP_X_FORWARDED_FOR'] = ip if ip

    post('/website_leads', body, env)
    last_response
  end

  def preflight(origin: nil)
    env = {}
    env['HTTP_ORIGIN'] = origin if origin
    custom_request('OPTIONS', '/website_leads', {}, env)
    last_response
  end

  private

  # CRLF line endings throughout — required by the multipart spec, and Rack's
  # parser will not find the field values without them.
  def build_multipart(fields)
    parts = fields.map do |name, value|
      "--#{BOUNDARY}\r\n" \
        "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n" \
        "#{value}\r\n"
    end
    "#{parts.join}--#{BOUNDARY}--\r\n"
  end
end

# The five UTM keys plus the two control fields, so a scenario's table only has
# to name the columns it cares about.
def website_lead_fields_from(table)
  table.rows_hash.transform_values(&:to_s)
end

Given('the website hosts are {string}') do |hosts|
  ENV['WEBSITE_HOSTS'] = hosts
end

Given('no website hosts are configured') do
  ENV.delete('WEBSITE_HOSTS')
end

# The page-render stamp the real client writes on load. Expressed relative to now
# so the scenario reads as intent ("filled in over a minute") rather than a magic
# epoch number.
Given('the form was rendered {int} seconds ago') do |seconds|
  @website_lead_ts = ((Time.current - seconds).to_f * 1000).to_i.to_s
end

When('the website submits a demo request from {string} with:') do |origin, table|
  @website_lead_client = WebsiteLeadClient.new
  fields = website_lead_fields_from(table)
  # Default to a plausibly-human fill time unless the scenario pinned one.
  fields['_ts'] ||= @website_lead_ts || ((Time.current - 45).to_f * 1000).to_i.to_s
  @website_lead_response = @website_lead_client.submit(fields, origin: origin)
end

# Deliberately built here rather than pasted into the feature: the point is that
# the length exceeds WebsiteLead::MESSAGE_MAX, and a wall of literal characters
# in the .feature file would hide that.
When('the website submits a demo request from {string} with a {int}-character message') do |origin, length|
  @website_lead_client = WebsiteLeadClient.new
  @website_lead_response = @website_lead_client.submit(
    {
      'name' => 'Nadia Okonkwo',
      'firm' => 'Meridian Capital',
      'email' => 'nadia@meridiancapital.example',
      'message' => 'x' * length,
      '_ts' => ((Time.current - 45).to_f * 1000).to_i.to_s
    },
    origin: origin
  )
end

When('the website submits {int} demo requests from IP {string} with:') do |count, ip, table|
  @website_lead_client = WebsiteLeadClient.new
  fields = website_lead_fields_from(table)
  fields['_ts'] ||= ((Time.current - 45).to_f * 1000).to_i.to_s
  @website_lead_responses = Array.new(count) do
    # A fresh render stamp per submission, exactly as a real repeat visitor would
    # have — otherwise the time check, not the throttle, would be what stops them.
    @website_lead_client.submit(fields.merge('_ts' => ((Time.current - 45).to_f * 1000).to_i.to_s),
                                origin: 'https://caphive.com', ip: ip)
  end
  @website_lead_response = @website_lead_responses.last
end

When('the website preflights the demo request from {string}') do |origin|
  @website_lead_client = WebsiteLeadClient.new
  @website_lead_response = @website_lead_client.preflight(origin: origin)
end

Then('the lead response status should be {int}') do |status|
  expect(@website_lead_response.status).to eq(status),
                                           "expected #{status}, got #{@website_lead_response.status}: " \
                                           "#{@website_lead_response.body.to_s.first(300)}"
end

Then('the last of those responses should be throttled') do
  # 429 is what Rack::Attack's throttled_responder returns. Asserting on the LAST
  # response specifically, so a scenario cannot pass because an early request
  # failed for an unrelated reason.
  expect(@website_lead_responses.last.status).to eq(429),
                                                 "expected the last request to be throttled (429), got " \
                                                 "#{@website_lead_responses.map(&:status).inspect}"
end

Then('{int} website lead(s) should exist') do |count|
  expect(WebsiteLead.count).to eq(count)
end

Then('a website lead should exist for {string}') do |email|
  expect(WebsiteLead.where(email: email)).to exist
end

Then('the stored lead should have {string} set to {string}') do |attribute, value|
  lead = WebsiteLead.order(:id).last
  expect(lead).to be_present, "no WebsiteLead was created"
  expect(lead.public_send(attribute).to_s).to eq(value)
end

Then('the stored lead should have a request IP recorded') do
  lead = WebsiteLead.order(:id).last
  expect(lead.request_ip).to be_present
end

# Cucumber runs the :inline ActiveJob adapter, so deliver_later has already run
# by the time the response comes back — assert on deliveries, never on enqueued
# jobs.
Then('a lead notification email should have been delivered') do
  expect(ActionMailer::Base.deliveries).not_to be_empty, "no email was delivered"
end

Then('no lead notification email should have been delivered') do
  expect(ActionMailer::Base.deliveries).to be_empty,
                                           "expected no email, got #{ActionMailer::Base.deliveries.map(&:subject).inspect}"
end

# Leads go to the commercial mailbox, deliberately NOT to SUPPORT_EMAIL_TO. This
# step pins the recipient so a future refactor cannot quietly reroute prospects
# into the support/exception firehose.
Then('the lead notification should have been sent to {string}') do |address|
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present, "no email was delivered"
  expect(mail.to).to include(address)
end

# Replying to the alert must reach the prospect, not the mailbox it landed in.
Then('the lead notification should reply to {string}') do |address|
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present, "no email was delivered"
  expect(mail.reply_to).to include(address)
end

Then('the notification should contain {string}') do |text|
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present, "no email was delivered"
  expect(mail.body.encoded).to include(text)
end

Then('the notification should not contain the raw text {string}') do |text|
  mail = ActionMailer::Base.deliveries.last
  expect(mail).to be_present, "no email was delivered"
  expect(mail.body.encoded).not_to include(text)
end

Then('the lead response should allow the origin {string}') do |origin|
  expect(@website_lead_response.headers['Access-Control-Allow-Origin']).to eq(origin)
end

Then('the lead response should not allow any origin') do
  expect(@website_lead_response.headers['Access-Control-Allow-Origin']).to be_nil,
                                                                          "an unlisted origin was echoed back: " \
                                                                          "#{@website_lead_response.headers['Access-Control-Allow-Origin'].inspect}"
end

Then('the lead response should never allow credentials') do
  expect(@website_lead_response.headers['Access-Control-Allow-Credentials']).to be_nil
end

Then('the lead response should vary on origin') do
  expect(@website_lead_response.headers['Vary'].to_s).to include('Origin')
end

# ---- staff screens ----

Given('a website lead exists from {string} at {string}') do |name, firm|
  @website_lead = WebsiteLead.create!(
    name: name, firm: firm, email: "#{name.parameterize}@example.com",
    role: "CFO or Finance", message: "We close 40 SPVs a year and the close is manual.",
    submitted_at: Time.current, utm_source: "linkedin", landing_page: "contact.html"
  )
end

When('the signed-in user requests the website leads index') do
  @lead_session = ActionDispatch::Integration::Session.new(Rails.application)
  @lead_session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
  @lead_session.get "/website_leads"
end

When('the signed-in user requests that website lead') do
  @lead_session = ActionDispatch::Integration::Session.new(Rails.application)
  @lead_session.post "/users/sign_in", params: { user: { email: @user.email, password: "password" } }
  @lead_session.get "/website_leads/#{@website_lead.id}"
end

When('an anonymous visitor requests the website leads index') do
  @lead_session = ActionDispatch::Integration::Session.new(Rails.application)
  @lead_session.get "/website_leads"
end

Then('the leads screen should be visible') do
  expect(@lead_session.response.status).to eq(200),
                                           "expected 200, got #{@lead_session.response.status} " \
                                           "(location: #{@lead_session.response.location.inspect})"
end

Then('the leads screen should show {string}') do |text|
  expect(@lead_session.response.body).to include(text)
end

Then('the leads screen should be denied') do
  expect(@lead_session.response.status).to be_between(300, 399),
                                           "expected a redirect away, got #{@lead_session.response.status}"
end
