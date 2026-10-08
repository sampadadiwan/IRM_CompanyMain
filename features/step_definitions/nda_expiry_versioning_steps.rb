# frozen_string_literal: true

# Step definitions for features/core/nda_expiry_versioning.feature
# Module 4 — Expiry Logic, Version Management & Re-acceptance:
#   version bump, version gate, resign_required flag, time-based expiry,
#   NdaConfigVersion audit, resolver expired status, and lapsed detection.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config)
#   and nda_status_steps.rb (LP investor with approved access, signatory tagging).

# ── Setup steps — Version ────────────────────────────────────────────────────

# Simulates a GP uploading a new NDA PDF by changing nda_document_data and
# incrementing the version via update_column (mirrors NdaConfigsController#update).
When("the GP uploads a new NDA PDF on the config") do
  new_doc = {
    id: "test/nda_configs/test_nda_v2.pdf",
    storage: "store",
    metadata: { size: 2048, filename: "test_nda_v2.pdf", mime_type: "application/pdf" }
  }.to_json
  @nda_config.update!(nda_document_data: new_doc)
  @nda_config.update_column(:version, @nda_config.version + 1)
  @nda_config.reload
end

# Creates a version 1 record for the NDA config (mirrors NdaConfigsController#create).
When("a version 1 record is created for the NDA config") do
  NdaConfigVersion.create!(
    nda_config: @nda_config,
    version: 1,
    nda_document_data: @nda_config.nda_document_data,
    resign_required: false,
    uploaded_by: @user
  )
end

# Creates an acceptance at a specific version number.
Given("the investor {string} has accepted the NDA at version {int}") do |_investor_name, version|
  @nda_acceptance = NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @lp_user,
    entity: @gp_entity,
    status: "accepted",
    nda_version: version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test)",
    accepted_at: Time.current
  )
end

# Bumps the NDA config version to a specific number via update_column.
Given("the NDA config version is bumped to {int}") do |version|
  @nda_config.update_column(:version, version)
  @nda_config.reload
end

# Sets the NDA config version without creating a version record.
Given("the NDA config version is set to {int}") do |version|
  @nda_config.update_column(:version, version)
  @nda_config.reload
end

# Creates a version record with a specific resign_required flag.
Given("a version {int} record exists with resign_required {word}") do |version, resign_str|
  resign = resign_str == "true"
  NdaConfigVersion.create!(
    nda_config: @nda_config,
    version: version,
    nda_document_data: fake_shrine_nda_document,
    resign_required: resign,
    uploaded_by: @user
  )
end

# ── Setup steps — Time-based Expiry ──────────────────────────────────────────

# Sets the NDA config to fixed_period validity with the given number of days.
Given("the NDA config has fixed_period validity of {int} days") do |days|
  @nda_config.update_columns(validity_type: "fixed_period", validity_days: days)
  @nda_config.reload
end

# Creates an acceptance N days ago (for time-expiry testing).
Given("the investor {string} accepted the NDA {int} days ago") do |_investor_name, days|
  @nda_acceptance = NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @lp_user,
    entity: @gp_entity,
    status: "accepted",
    nda_version: @nda_config.version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test)",
    accepted_at: days.days.ago
  )
end

# Sets the NDA config to specific_date validity with a date in the past.
Given("the NDA config has specific_date validity set to {int} days ago") do |days|
  @nda_config.update_columns(validity_type: "specific_date", validity_date: days.days.ago.to_date)
  @nda_config.reload
end

# Sets the NDA config to specific_date validity with a date in the future.
Given("the NDA config has specific_date validity set to {int} days from now") do |days|
  @nda_config.update_columns(validity_type: "specific_date", validity_date: days.days.from_now.to_date)
  @nda_config.reload
end

# ── Action steps — Update ────────────────────────────────────────────────────

# GP updates contact_email (for testing past-date validation bypass).
When("the GP updates the NDA config contact_email to {string}") do |email|
  @nda_config.update!(contact_email: email)
  @nda_config.reload
end

# ── Assertion steps — Version ────────────────────────────────────────────────

# Verifies the NDA config version.
Then("the NDA config version should be {int}") do |expected|
  expect(@nda_config.reload.version).to eq(expected)
end

# ── Assertion steps — Version History ────────────────────────────────────────

# Verifies the count of NdaConfigVersion records for the current NDA config.
Then("there should be {int} NDA config version record(s)") do |count|
  expect(NdaConfigVersion.where(nda_config: @nda_config).count).to eq(count)
end

# Verifies the latest version record's version number.
Then("the latest version record version should be {int}") do |expected|
  latest = NdaConfigVersion.where(nda_config: @nda_config).order(version: :desc).first
  expect(latest).to be_present
  expect(latest.version).to eq(expected)
end

# Verifies the latest version record's uploaded_by.
Then("the latest version record uploaded_by should be the GP user") do
  latest = NdaConfigVersion.where(nda_config: @nda_config).order(version: :desc).first
  expect(latest.uploaded_by).to eq(@user)
end

# Verifies version 1 record's resign_required flag.
Then("the version {int} record resign_required should be {word}") do |version, expected_str|
  expected = expected_str == "true"
  record = NdaConfigVersion.find_by!(nda_config: @nda_config, version: version)
  expect(record.resign_required).to eq(expected)
end

# Verifies cascade delete of version records.
Then("there should be {int} NDA config version records for the config") do |count|
  expect(NdaConfigVersion.where(nda_config_id: @nda_config.id).count).to eq(count)
end

# ── Assertion steps — Version Gate ───────────────────────────────────────────

# Uses the same logic as DocumentsController#acceptance_version_current?.
Then("the acceptance should be version-current for the NDA config") do
  expect(acceptance_version_current?(@nda_acceptance, @nda_config)).to be true
end

Then("the acceptance should not be version-current for the NDA config") do
  expect(acceptance_version_current?(@nda_acceptance, @nda_config)).to be false
end

# ── Assertion steps — Time Expiry ────────────────────────────────────────────

# Uses the same logic as DocumentsController#acceptance_time_valid? (inverted).
Then("the acceptance should be time-expired for the NDA config") do
  expect(acceptance_time_valid?(@nda_acceptance, @nda_config)).to be false
end

Then("the acceptance should not be time-expired for the NDA config") do
  expect(acceptance_time_valid?(@nda_acceptance, @nda_config)).to be true
end

# ── Assertion steps — Resolver Expiry Reason ─────────────────────────────────

# Verifies the expiry_reason on the resolver's investor row.
Then("the investor {string} expiry_reason should be {string}") do |investor_name, expected|
  row = @resolver_result[:investor_rows].find { |r| r[:investor].investor_name == investor_name }
  expect(row).to be_present, "Investor #{investor_name} not found in resolver result"
  expect(row[:expiry_reason]).to eq(expected)
end

# Verifies the expired counter.
Then("the resolver counters should show expired {int}") do |count|
  expect(@resolver_result[:counters][:expired]).to eq(count)
end

# ── Assertion steps — Lapsed Detection ───────────────────────────────────────

# Checks that a specific_date NDA with past validity_date is identified as lapsed.
Then("the NDA config should be identified as lapsed") do
  expect(@nda_config.validity_type).to eq("specific_date")
  expect(@nda_config.validity_date).to be < Date.current
end

Then("the NDA config should not be identified as lapsed") do
  lapsed = @nda_config.validity_type == "specific_date" && @nda_config.validity_date < Date.current
  expect(lapsed).to be false
end

# ── Helper methods (mirrors DocumentsController private methods) ─────────────

# @param acceptance [NdaAcceptance] the LP's latest acceptance record
# @param nda_config [NdaConfig] the NDA config to check against
# @return [Boolean] true if acceptance is still valid for the current version
def acceptance_version_current?(acceptance, nda_config)
  return true if acceptance.nda_version == nda_config.version

  resign_exists = NdaConfigVersion.where(
    nda_config_id: nda_config.id,
    version: (acceptance.nda_version + 1)..nda_config.version,
    resign_required: true
  ).exists?

  return false if resign_exists

  NdaConfigVersion.where(nda_config_id: nda_config.id).exists?
end

# @param acceptance [NdaAcceptance] the LP's latest acceptance record
# @param nda_config [NdaConfig] the NDA config to check against
# @return [Boolean] true if the acceptance has not expired
def acceptance_time_valid?(acceptance, nda_config)
  case nda_config.validity_type
  when "until_revoked"
    true
  when "fixed_period"
    acceptance.accepted_at + nda_config.validity_days.days > Time.current
  when "specific_date"
    nda_config.validity_date >= Date.current
  else
    true
  end
end
