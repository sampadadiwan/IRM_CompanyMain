# frozen_string_literal: true

# Steps for the LP mobile app's API (features/mobile/*.feature).
# openspec/changes/lp-mobile-app/design.md#worked-examples — the H/E/X IDs in the features.

# A phone talking to /api/mobile/v1: one Rack::Test session per phone, JSON in and out, with the
# headers the Expo app sends.
class MobilePhone
  include Rack::Test::Methods

  attr_accessor :access_token, :refresh_token, :challenge, :app_version, :language
  attr_reader :name, :install_id, :platform

  def initialize(name, platform: nil)
    @name = name
    @install_id = "install-#{name.parameterize}"
    @platform = platform || (/pixel|android|galaxy/i.match?(name) ? "android" : "ios")
  end

  def app
    Rails.application
  end

  def device_attrs
    { install_id:, platform:, name:, app_version: app_version || "1.0.0" }
  end

  def call(verb, path, body = nil)
    header "Content-Type", "application/json"
    header "Accept", "application/json"
    header "X-App-Version", app_version || "1.0.0"
    header "Accept-Language", language || "en-IN"
    header "Authorization", access_token ? "Bearer #{access_token}" : nil
    send(verb, path, body&.to_json)
    last_response
  end

  def json
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end
end

module MobileApiWorld
  def phones
    @phones ||= {}
  end

  def phone(name)
    phones[name] ||= MobilePhone.new(name)
  end

  def last_phone
    @last_phone || raise("no phone has made a request yet")
  end

  def mobile_user(email)
    User.find_by!(email:)
  end

  # Fund manager entity and an investor (with its own investor entity) under it
  def mobile_fund_manager(name)
    Entity.find_by(name:) || FactoryBot.create(:entity, name:, entity_type: "Investment Fund", enable_funds: true)
  end

  def mobile_investor(investor_name, fund_manager)
    investor_entity = Entity.find_by(name: investor_name) ||
                      FactoryBot.create(:entity, name: investor_name, entity_type: "Investor")
    Investor.find_by(entity_id: fund_manager.id, investor_entity_id: investor_entity.id) ||
      FactoryBot.create(:investor, entity: fund_manager, investor_entity:, investor_name:,
                                   primary_email: investor_entity.primary_email)
  end

  def mobile_request(phone_name, verb, path, body = nil)
    @last_phone = phone(phone_name)
    @last_phone.call(verb, path, body)
  end

  # Signs a phone in directly through the registry (the sign-in flow itself is covered by
  # mobile_sign_in.feature)
  def mobile_sign_in!(user, phone_name)
    ph = phone(phone_name)
    device, token = MobileDevice.register!(user, **ph.device_attrs)
    ph.access_token = token.access_token
    ph.refresh_token = token.refresh_token
    device
  end
end
World(MobileApiWorld)

# ── Setup ────────────────────────────────────────────────────────────────────

Given("a mobile investor {string} of {string} with fund manager {string}") do |email, investor_name, fm_name|
  fund_manager = mobile_fund_manager(fm_name)
  investor = mobile_investor(investor_name, fund_manager)
  first = email.split("@").first.capitalize
  last = investor_name.split.first
  user = User.find_by(email:) || FactoryBot.create(:user, email:, first_name: first, last_name: last,
                                                          entity: investor.investor_entity)
  FactoryBot.create(:investor_access, entity: fund_manager, investor:, user:, email:, first_name: first,
                                      last_name: last, approved: true)
  @user = user.reload
end

Given("{string} is an employee of the fund manager {string}") do |email, fm_name|
  fund_manager = mobile_fund_manager(fm_name)
  @user = User.find_by(email:) || FactoryBot.create(:user, email:, entity: fund_manager)
end

Given("{string} has authenticator two-factor") do |email|
  mobile_user(email).update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret,
                             two_factor_mode: "authenticator")
end

Given("{string} has sms two-factor") do |email|
  mobile_user(email).update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret,
                             two_factor_mode: "sms", phone: "4155550134", call_code: "1",
                             skip_phone_validation: true)
end

Given("{string} has two-factor switched on but no method set up") do |email|
  mobile_user(email).update!(two_factor_enabled: true, two_factor_mode: nil)
end

Given("{string} is locked out") do |email|
  mobile_user(email).lock_access!(send_instructions: false)
end

Given("{string} is signed in on the phone {string}") do |email, phone_name|
  mobile_sign_in!(mobile_user(email), phone_name)
end

Given("{string} already has {int} live phones") do |email, count|
  user = mobile_user(email)
  count.times do |i|
    travel_to((count - i).hours.ago) { mobile_sign_in!(user, "Old phone #{i + 1}") }
  end
end

Given("the phone {string} was last used {int} days ago") do |phone_name, days|
  MobileDevice.find_by!(install_id: phone(phone_name).install_id).update_columns(last_used_at: days.days.ago)
end

Given("the phone {string} sends app version {string}") do |phone_name, version|
  phone(phone_name).app_version = version
end

Given("the minimum app version is {string}") do |version|
  allow(Api::Mobile::V1::BaseController).to receive(:min_app_version).and_return(version)
end

Given("{string} has a website API token") do |email|
  user = mobile_user(email)
  token = Devise::Api::Token.create!(resource_owner: user, access_token: Devise::Api::Token.generate_uniq_access_token(user),
                                     refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user), expires_in: 3600)
  phone("Website client").access_token = token.access_token
end

# ── Sign-in requests ─────────────────────────────────────────────────────────

When("{string} signs in on the phone {string} with password {string}") do |email, phone_name, password|
  mobile_request(phone_name, :post, "/api/mobile/v1/session",
                 { email:, password:, device: phone(phone_name).device_attrs })
  phone(phone_name).challenge = last_phone.json["challenge"]
  if last_phone.json["access_token"]
    phone(phone_name).access_token = last_phone.json["access_token"]
    phone(phone_name).refresh_token = last_phone.json["refresh_token"]
  end
end

When("the phone {string} enters the current authenticator code for {string}") do |phone_name, email|
  code = mobile_user(email).reload.current_otp
  step %(the phone "#{phone_name}" enters the code "#{code}")
end

When("the phone {string} enters the code {string}") do |phone_name, code|
  ph = phone(phone_name)
  mobile_request(phone_name, :post, "/api/mobile/v1/session/verify",
                 { challenge: ph.challenge, code:, device: ph.device_attrs })
  if last_phone.json["access_token"]
    ph.access_token = last_phone.json["access_token"]
    ph.refresh_token = last_phone.json["refresh_token"]
  end
end

When("the phone {string} asks for the code again") do |phone_name|
  mobile_request(phone_name, :post, "/api/mobile/v1/session/resend", { challenge: phone(phone_name).challenge })
end

When("the phone {string} refreshes its session") do |phone_name|
  ph = phone(phone_name)
  @old_access_token = ph.access_token
  mobile_request(phone_name, :post, "/api/mobile/v1/session/refresh", { refresh_token: ph.refresh_token })
  ph.access_token = last_phone.json["access_token"] if last_phone.json["access_token"]
end

When("the phone {string} uses its old access token") do |phone_name|
  phone(phone_name).access_token = @old_access_token
end

When("{int} minutes pass") do |minutes|
  travel(minutes.minutes)
end

When("{int} minutes and {int} seconds pass") do |minutes, seconds|
  travel(minutes.minutes + seconds.seconds)
end

# ── Generic requests ─────────────────────────────────────────────────────────

When("the phone {string} requests {string}") do |phone_name, path|
  mobile_request(phone_name, :get, path)
end

When("the phone {string} posts to {string}") do |phone_name, path|
  mobile_request(phone_name, :post, path, {})
end

When("the phone {string} posts to {string} with:") do |phone_name, path, json|
  mobile_request(phone_name, :post, path, JSON.parse(json))
end

When("the phone {string} sends {string} to {string} with:") do |phone_name, verb, path, json|
  mobile_request(phone_name, verb.downcase.to_sym, path, JSON.parse(json))
end

# ── Assertions ───────────────────────────────────────────────────────────────

Then("the phone gets the status {int}") do |status|
  expect(last_phone.last_response.status).to eq(status), "got #{last_phone.last_response.status}: #{last_phone.last_response.body}"
end

Then("the phone gets the error {string}") do |code|
  expect(last_phone.json["error"]).to eq(code), "body: #{last_phone.last_response.body}"
end

Then("the phone sees the message {string}") do |message|
  expect(last_phone.json["message"]).to eq(message)
end

Then("the phone gets a challenge for {string} two-factor with {int} attempts") do |method, attempts|
  expect(last_phone.last_response.status).to eq(202)
  expect(last_phone.json).to include("method" => method, "attempts_left" => attempts)
  expect(last_phone.json["challenge"]).to be_present
  expect(last_phone.json).not_to have_key("access_token")
end

Then("the phone gets a session") do
  expect(last_phone.last_response.status).to eq(201), "body: #{last_phone.last_response.body}"
  expect(last_phone.json).to include("access_token", "refresh_token", "device_id")
end

Then("the JSON at {string} is {string}") do |path, value|
  # {call3} stands for Capital Call 3's id in the shared setup
  value = value.gsub("{call3}") { arka[:call3].id.to_s } if respond_to?(:arka)
  actual = path.split(".").reduce(last_phone.json) { |memo, key| memo.is_a?(Array) ? memo[key.to_i] : memo&.dig(key) }
  expect(actual.to_s).to eq(value)
end

Then("{string} has a live phone {string}") do |email, phone_name|
  device = mobile_user(email).mobile_devices.find_by(install_id: phone(phone_name).install_id)
  expect(device).to be_present
  expect(device).to be_live
  expect(device.name).to eq(phone_name)
end

Then("{string} has {int} live phone(s)") do |email, count|
  expect(MobileDevice.live.where(user: mobile_user(email)).count).to eq(count)
end

Then("{string} has {int} phone record(s)") do |email, count|
  expect(mobile_user(email).mobile_devices.count).to eq(count)
end

Then("the phone {string} is signed out because {string}") do |phone_name, reason|
  device = MobileDevice.find_by!(install_id: phone(phone_name).install_id)
  expect(device.revoked_at).to be_present
  expect(device.revoked_reason).to eq(reason)
end

Then("{string} has no phones") do |email|
  expect(mobile_user(email).mobile_devices).to be_empty
end

Then("{string} has {int} failed password attempt(s)") do |email, count|
  expect(mobile_user(email).failed_attempts).to eq(count)
end

Then("a text message code was sent {int} time(s)") do |count|
  expect(@twilio.sent.size).to eq(count)
end

# ── Website: Profile › Devices ───────────────────────────────────────────────

When("I visit the Mobile Devices page") do
  visit("/users/mobile_devices")
end

When("I sign out the phone {string} on the Mobile Devices page") do |phone_name|
  device = MobileDevice.find_by!(install_id: phone(phone_name).install_id)
  # The confirmation modal's button (rack_test does not run Bootstrap, so the modal markup is
  # submitted directly — the same form a browser posts after the user confirms)
  click_on("confirm_sign_out_device_#{device.id}")
end

Given("the phone {string} was signed out on the website") do |phone_name|
  MobileDevice.find_by!(install_id: phone(phone_name).install_id).revoke!(reason: "website_sign_out")
end

When("the investor user {string} is deactivated") do |email|
  mobile_user(email).update!(active: false)
end

When("the user {string} changes their password") do |email|
  mobile_user(email).update!(password: "N3w-Passw0rd!", password_confirmation: "N3w-Passw0rd!")
end

Given("the phone {string} uses the language {string}") do |phone_name, language|
  phone(phone_name).language = language
end

When("{string} asks the website's token endpoint for a token with password {string}") do |email, password|
  mobile_request("Website client", :post, "/users/tokens/sign_in", { email:, password: })
end

When("the phone {string} refreshes through the website's token endpoint") do |phone_name|
  ph = phone(phone_name)
  # devise-api reads the refresh token from the Authorization header
  saved = ph.access_token
  ph.access_token = ph.refresh_token
  mobile_request(phone_name, :post, "/users/tokens/refresh", {})
  ph.access_token = saved
end
