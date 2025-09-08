Given(/^a user "([^"]+)" exists in region "([^"]+)" with regions "([^"]+)"$/) do |email, primary, regions|
  @entity = FactoryBot.create(:entity, first_name: "Acme", primary_region: primary, entity_type: "Investment Fund")
  @user = FactoryBot.create(:user, email:, primary_region: primary, regions: regions, entity: @entity)
  @user.update!(first_name: "Jane", phone: "4155551212")

  puts @user.to_json
end

And(/^the user has roles "([^"]+)"$/) do |csv|
  names = csv.split(",").map(&:strip)
  names.each do |name|
    @user.add_role name.to_sym
  end
end

And(/^the sync API for "([^"]+)" is stubbed for UPSERT$/) do |region|
  stub_sync_upsert_for(region) { |json| @last_seen ||= {}; @last_seen[region] = json }
end

When('I trigger the orchestrator for that user with force {string}') do |force|
  MultiSiteUserSyncOrchestrator.call(user: @user, force_all: force == "true")
end

Then(/^a signed UPSERT should be sent to "([^"]+)"$/) do |region|
  base = ENV.fetch("SYNC_API_BASE_URL_#{region}")
  url  = URI.join("#{base}/", "/internal/sync/users").to_s
  WebMock::API.assert_requested(:post, url, times: 1)
end

Then(/^no UPSERT should be sent to "([^"]+)"$/) do |region|
  base = ENV.fetch("SYNC_API_BASE_URL_#{region}")
  url  = URI.join("#{base}/", "/internal/sync/users").to_s
  WebMock::API.assert_not_requested(:post, url)
end

And(/^the UPSERT body should include the user's email and roles$/) do
  json = @last_seen.values.last # from stub block
  expect(json["user"]["email"]).to eq(@user.email)
  expect(json["roles"].map{|r| r["name"]}).to match_array(@user.roles.pluck(:name))
  expect(json["ccf_hex"]).to match(/\A[0-9a-f]{64}\z/)
end



When(/^I enqueue an upsert job to "([^"]+)"$/) do |region|
  MultiSiteUserSyncJob.perform_later(@user.id, region, force: true)
end



When(/^I orchestrate with previous regions "([^"]+)"$/) do |prev|
  MultiSiteUserSyncOrchestrator.call(user: @user, previous_regions: prev)
end

And(/^the sync API for "([^"]+)" is stubbed for DISABLE$/) do |region|
  stub_sync_disable_for(region) { |json| @last_disable = json }
end

Then(/^a signed DISABLE should be sent to "([^"]+)"$/) do |region|
  base = ENV.fetch("SYNC_API_BASE_URL_#{region}")
  url  = URI.join("#{base}/", "/internal/sync/users/disable").to_s
  WebMock::API.assert_requested(:post, url, times: 1)
end

And(/^the user is already synced$/) do
  @user.update!(last_synced_ccf_hex: @user.ccf_hex)
end

When(/^I change the user's entity name to "([^"]+)"$/) do |name|
  @user.entity.update!(name:)
  @user.reload # Reload the user to get the updated entity data
end


Then(/^the UPSERT roles should be "([^"]+)"$/) do |csv|
  expected = csv.split(",").map(&:strip)
  json = @last_seen["US"]
  names = json["roles"].map{|r| r["name"]}
  expect(names).to eq(expected) # your builder sorts; adjust if different
end

# features/step_definitions/sync_steps.rb

And(/^the UPSERT endpoint for "([^"]+)" responds (\d+)$/) do |region, code|
  # Reuse the HMAC-verifying stub helper, but force the status code
  stub_sync_upsert_for(region, status: code.to_i)
end

When(/^I perform an upsert to "([^"]+)" capturing errors$/) do |region|
  @sync_error = nil
  begin
    # Run the job immediately/deterministically
    MultiSiteUserSyncJob.perform_now(@user.id, region, force: true)
  rescue => e
    @sync_error = e
  end
end

Then(/^a retryable sync error should occur$/) do
  raise "Expected a RetryableError, but none was raised" unless @sync_error
  unless @sync_error.is_a?(SyncApiClient::RetryableError)
    raise "Expected RetryableError, got #{@sync_error.class}: #{@sync_error.message}"
  end
end

Then(/^no sync exception should be raised$/) do
  if defined?(@sync_error) && @sync_error
    raise "Did not expect an exception, but got #{@sync_error.class}: #{@sync_error.message}"
  end
end



# frozen_string_literal: true

# Assumptions:
# - User includes CanonicalFingerprintCCF (ccf_hex, needs_sync?, mark_synced_now!)
# - User has_many :roles; Role has attribute :name
# - User belongs_to :entity; Entity has attributes incl. :name, :primary_region
# - Telemetry fields exist (e.g., last_sign_in_at); if missing in your schema, guard those steps.

Given(/^a baseline user "([^"]+)" with primary region "([^"]+)" and regions "([^"]+)"$/) do |email, primary, regions|
  @entity = FactoryBot.create(:entity, first_name: "Acme", primary_region: primary, entity_type: "Investment Fund")
  @user = FactoryBot.create(:user, email:, primary_region: primary, regions: regions, entity: @entity)
  @user.update!(first_name: "Jane", phone: "4155551212")
end


When(/^I capture the user's CCF$/) do
  @ccf_before = @user.ccf_hex
end

When(/^I update the user field "([^"]+)" to "([^"]+)"$/) do |field, value|
  @user.update!(field => value)
  @user.reload
end

When(/^I update the telemetry field "([^"]+)" to now$/) do |field|
  if @user.respond_to?(:"#{field}=")
    @user.update!(field => Time.current)
    @user.reload
  else
    # If your schema doesn't have this field, skip (keeps test portable)
  end
end

When(/^I set the user roles to "([^"]+)"$/) do |csv|
  names = csv.split(",").map(&:strip)
  @user.roles = names.map { |n| Role.find_or_create_by!(name: n) }
  @user.reload
end

When(/^I update the entity field "([^"]+)" to "([^"]+)"$/) do |field, value|
  @user.entity.update!(field => value)
  @user.reload
end

Then(/^the user's CCF should change$/) do
  raise "Expected CCF to change" if @user.ccf_hex == @ccf_before
end

Then(/^the user's CCF should not change$/) do
  raise "Expected CCF to remain same" if @user.ccf_hex != @ccf_before
end

Given(/^the user is already marked synced$/) do
  @user.update!(last_synced_ccf_hex: @user.ccf_hex, last_synced_at: Time.current)
  @user.reload
end

When(/^I set user regions to "([^"]+)"$/) do |csv|
  @user.update!(regions: csv)
  @user.reload
end

Then(/^needs_sync\? should be "([^"]+)"$/) do |expected|
  actual = @user.needs_sync? ? "true" : "false"
  raise "Expected #{expected}, got #{actual}" unless actual == expected
end

When(/^I mark the user as synced now$/) do
  @user.mark_synced_now!
  @user.reload
end

















# ---------- Background / config ----------
Given(/^the server region is "([^"]+)" and an HMAC secret is configured$/) do |region|
  ENV["REGION"] = region
  ENV["SYNC_API_HMAC_#{region}"] ||= SecureRandom.hex(32)
end


# ---------- UPSERT payload prep ----------

When('I prepare an UPSERT payload for {string} from origin {string} with roles {string} existing {string}') do |email, origin, roles_csv, existing_user|

  roles = roles_csv.split(",").map { |n| { name: n.strip } }.uniq

  @origin_user = FactoryBot.build(:user, email:, primary_region: origin, regions: "IN,US")
  @origin_entity = FactoryBot.build(:entity, name: "Acme Holdings", entity_type: "Investment Fund")
  @origin_user.entity_type = @origin_entity.entity_type
  @origin_user.entity = @origin_entity

  if existing_user == "true"
    # Create existing user in DB to simulate update scenario
    @origin_user.save!
  end

  @payload = {
    action: "UPSERT",
    event_id: SecureRandom.uuid,
    as_of: Time.now.utc.iso8601(3),
    origin_region: origin,
    target_region: ENV["REGION"], # not strictly required by server, but good for logging
    ccf_hex: SecureRandom.hex(32), # any 64-hex works; idempotency uses exact match
    user: @origin_user.as_json,
    entity: @origin_entity.as_json,
    roles: roles
  }
end

# Reuse the most recent UPSERT payload
Given(/^a user exists via a prior UPSERT for "([^"]+)"$/) do |email|
  step %(I prepare an UPSERT payload for "#{email}" from origin "IN" with roles "viewer" existing "false")
  step %(I POST the signed request to "/internal/sync/users")
  expect(@last_response.status).to eq(200)
  parsed = JSON.parse(@last_response.body)
  expect(parsed["applied"]).to eq(true)
end

Given(/^I reuse the last UPSERT payload$/) do
  expect(@payload).to be_present
end

# Existing user with specified primary
Given(/^an existing user "([^"]+)" with primary_region "([^"]+)"$/) do |email, pr|
  entity = FactoryBot.create(:entity)
  @existing_user = FactoryBot.create(:user, email:, primary_region: pr, regions: "IN,US", entity:)
end

# ---------- DISABLE payload prep ----------
Given(/^I prepare a DISABLE payload for "([^"]+)" from origin "([^"]+)"$/) do |email, origin|
  @payload = {
    action: "DISABLE",
    event_id: SecureRandom.uuid,
    as_of: Time.now.utc.iso8601(3),
    origin_region: origin,
    target_region: ENV["REGION"],
    email: email,
    reason: "removed_from_regions"
  }
end

# ---------- DIGEST payload prep ----------
Given(/^I prepare a DIGEST payload for emails "([^"]+)"$/) do |csv|
  emails = csv.split(",").map { |e| e.strip.downcase }
  @payload = { emails: emails }
end

# ---------- Signed POST ----------
When(/^I POST the signed request to "([^"]+)"$/) do |path|
  body = JSON.generate(@payload)
  ts   = Time.now.utc.iso8601(3)
  # Use the origin_region from the payload to fetch the correct HMAC secret for signing
  origin_region_for_signing = @payload["origin_region"] || @payload[:origin_region] || "IN"
  secret = ENV.fetch("SYNC_API_HMAC_#{origin_region_for_signing}")
  data = "POST\n#{path}\n#{ts}\n#{Digest::SHA256.hexdigest(body)}"
  sig  = OpenSSL::HMAC.hexdigest("SHA256", secret, data)

  header "Content-Type", "application/json"
  header "Accept", "application/json"
  header "X-Timestamp", ts
  header "X-Region", origin_region_for_signing # Ensure X-Region header matches the secret used for signing
  header "X-Idempotency-Key", (@payload["event_id"] || @payload[:event_id] || SecureRandom.uuid)
  header "X-Signature", sig

  post path, body
  @last_response = last_response
end

# ---------- Assertions ----------
Then(/^the response status should be (\d+)$/) do |code|
  expect(@last_response.status).to eq(code.to_i), @last_response.body
end

Then(/^the JSON response should include "([^"]+)" = (true|false)$/) do |key, val|
  json = JSON.parse(@last_response.body)
  expect(json[key]).to eq(val == "true")
end

Then(/^the JSON response should include "([^"]+)" = "([^"]+)"$/) do |key, val|
  json = JSON.parse(@last_response.body)
  expect(json[key]).to eq(val)
end

Then(/^a user "([^"]+)" should exist with primary_region "([^"]+)" and regions "([^"]+)"$/) do |email, pr, regions_csv|
  user = User.find_by!(email: email)
  expect(user.primary_region.to_s.upcase).to eq(pr)
  expected = regions_csv.split(",").map { |r| r.strip.upcase }.sort
  actual = if user.regions.is_a?(String)
             user.regions.split(",").map { |r| r.strip.upcase }.sort
           else
             Array(user.regions).map { |r| r.to_s.upcase }.sort
           end
  expect(actual).to eq(expected)


  user.first_name.should eq @origin_user.first_name
  user.last_name.should eq @origin_user.last_name
  user.phone.should eq @origin_user.phone
  user.regions.should eq @origin_user.regions
  user.primary_region.should eq @origin_user.primary_region
  user.permissions.should eq @origin_user.permissions
  user.entity_type.should eq @origin_user.entity_type
  user.extended_permissions.should eq @origin_user.extended_permissions
  user.entity.name.should eq @origin_entity.name
  user.entity.entity_type.should eq @origin_entity.entity_type
  expect(user.access_rights_cache).to eq({})

  user.entity_id.should eq @origin_entity.id if @origin_entity.persisted?
  user.active.should be true
end

Then(/^the user "([^"]+)" should have roles "([^"]+)"$/) do |email, csv|
  names = csv.split(",").map(&:strip).sort
  user  = User.find_by!(email: email)
  actual = if user.respond_to?(:roles)
             user.roles.map { |r| r.respond_to?(:name) ? r.name : r.to_s }.sort
           elsif user.respond_to?(:roles_list)
             Array(user.roles_list).sort
           else
             [] # adapt if you store roles differently
           end
  expect(actual).to eq(names)
end

Then(/^the user's last_synced_ccf_hex should equal the payload CCF$/) do
  json = JSON.parse(@last_response.body)
  applied_ccf = json["ccf_hex_applied"] || @payload["ccf_hex"]
  user = User.find_by!(email: @payload[:user]["email"])
  expect(user.last_synced_ccf_hex).to eq(applied_ccf)
end

Then(/^an entity named "([^"]+)" should exist$/) do |name|
  expect(Entity.where(name: name).exists?).to be(true)
end

Then(/^the user "([^"]+)" should be disabled$/) do |email|
  user = User.find_by!(email: email)
  user.active.should be false
end

Then(/^the JSON response "digests" should have a non-empty value for "([^"]+)"$/) do |email|
  json = JSON.parse(@last_response.body)
  val = json.dig("digests", email)
  expect(val).to be_a(String).and(match(/\A[0-9a-f]{64}\z/).or(be_present))
end

Then(/^the JSON response "digests" should have a null value for "([^"]+)"$/) do |email|
  json = JSON.parse(@last_response.body)
  expect(json.dig("digests", email)).to be_nil
end