# frozen_string_literal: true

# Step definitions for features/core/nda_status.feature
# Module 3 — NDA Status Dashboard: model-level tests for stakeholder-level
# exemption (InvestorAccess.exempt_from_nda), NdaSignatory, NdaStatusResolver,
# gate exemption check, and NdaStatusPolicy.
#
# Changed: Replaced NdaExemption steps with InvestorAccess.exempt_from_nda steps.
# Why: Per product decision (2026-10-05) — exemption is stakeholder-level, not user-level.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config)
#   and nda_acceptance_steps.rb (LP user setup).

# ── Setup steps ──────────────────────────────────────────────────────────────

# Creates an LP investor with approved InvestorAccess to the GP entity,
# plus a user belonging to that investor's entity.
# @param investor_name [String] the investor's display name
Given("there is an LP investor {string} with approved access to the GP entity") do |investor_name|
  @lp_entity ||= Entity.create!(
    name: "LP Entity", entity_type: "Limited Partner", primary_email: "lp_entity@example.com"
  )
  # Changed: Use @lp_entity's primary_email so the Investor#update_name callback
  # finds the existing entity instead of creating a new one named after the investor.
  @lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: @lp_entity,
    category: "LP",
    primary_email: @lp_entity.primary_email
  )
  @lp_user ||= User.create!(
    email: "lp_test_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "LP",
    last_name: "User"
  )
  # Changed: Supply email/name so the before_validation :update_user callback
  # (which calls email.strip) doesn't raise NoMethodError on nil.
  @lp_investor_access = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor,
    user: @lp_user,
    email: @lp_user.email,
    first_name: @lp_user.first_name,
    last_name: @lp_user.last_name,
    approved: true
  )
  # Changed: Create folder-level AccessRight so Investor.owner_access_rights finds this investor.
  # Why: NdaStatusResolver now uses folder-scoped access rights instead of entity-level InvestorAccess.
  #   Without an AccessRight on the data room folder, the resolver returns 0 investors.
  if @data_room_folder
    AccessRight.find_or_create_by!(
      owner: @data_room_folder,
      entity_id: @gp_entity.id,
      access_to_investor_id: @lp_investor.id,
      cascade: false
    )
  end
end

# Creates an LP investor with unapproved InvestorAccess (approved: false).
Given("there is an LP investor {string} with unapproved access to the GP entity") do |investor_name|
  @lp_entity ||= Entity.create!(
    name: "LP Entity", entity_type: "Limited Partner", primary_email: "lp_entity@example.com"
  )
  # Changed: Use @lp_entity's primary_email so the Investor#update_name callback
  # finds the existing entity instead of creating a new one named after the investor.
  @lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: @lp_entity,
    category: "LP",
    primary_email: @lp_entity.primary_email
  )
  @lp_user ||= User.create!(
    email: "lp_test_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "LP",
    last_name: "User"
  )
  # Changed: Supply email/name so the before_validation :update_user callback
  # (which calls email.strip) doesn't raise NoMethodError on nil.
  InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor,
    user: @lp_user,
    email: @lp_user.email,
    first_name: @lp_user.first_name,
    last_name: @lp_user.last_name,
    approved: false
  )
end

# Creates an NdaAcceptance with status "accepted" for the named investor.
Given("the investor {string} has accepted the NDA") do |_investor_name|
  NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @lp_user,
    entity: @gp_entity,
    status: "accepted",
    nda_version: @nda_config.version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test)",
    accepted_at: Time.current
  )
end

# Creates an NdaAcceptance with status "declined" for the named investor.
Given("the investor {string} has declined the NDA") do |_investor_name|
  NdaAcceptance.create!(
    nda_config: @nda_config,
    investor: @lp_investor,
    user: @lp_user,
    entity: @gp_entity,
    status: "declined",
    nda_version: @nda_config.version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test)",
    declined_at: Time.current
  )
end

# Changed: Sets exempt_from_nda on the LP investor access record.
# Why: Stakeholder-level exemption replaces user-level NdaExemption table.
Given("the investor access has exempt_from_nda set to true") do
  @lp_investor_access.update!(exempt_from_nda: true)
end

# Creates a GP user from a different entity for cross-entity policy tests.
Given("there is a GP user from a different entity") do
  @other_gp_entity = Entity.create!(
    name: "Other GP", entity_type: "Investment Fund", primary_email: "other_gp@example.com"
  )
  @other_gp_user = User.create!(
    email: "other_gp_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @other_gp_entity,
    first_name: "Other",
    last_name: "GP"
  )
  # Changed: Use unscoped add_role (no entity arg) to match app convention.
  # Why: Rolify.resource_types is empty — passing an entity triggers a
  # "Resource type is not included in the list" validation error.
  @other_gp_user.add_role(:company_admin)
end

# ── Action steps — exempt_from_nda ──────────────────────────────────────────

# GP sets exempt_from_nda to true on the investor access.
When("the GP sets exempt_from_nda to true for the investor access") do
  @lp_investor_access.update!(exempt_from_nda: true)
end

# Destroys the NDA config to test cascade behavior.
When("the NDA config is destroyed") do
  @nda_config.destroy!
end

# ── Action steps — Resolver ──────────────────────────────────────────────────

# Runs the NdaStatusResolver for the current NDA config and folder.
When("the resolver resolves NDA status for the folder") do
  @resolver_result = NdaStatusResolver.resolve(@nda_config, @data_room_folder)
end

# ── Assertion steps — exempt_from_nda ───────────────────────────────────────

# Verifies the investor access exempt_from_nda is false (default).
Then("the investor access exempt_from_nda should be false") do
  expect(@lp_investor_access.reload.exempt_from_nda).to be false
end

# Verifies the investor access exempt_from_nda is true.
Then("the investor access exempt_from_nda should be true") do
  expect(@lp_investor_access.reload.exempt_from_nda).to be true
end

# ── Assertion steps — Resolver ───────────────────────────────────────────────

# Verifies the resolver result includes the named investor.
Then("the resolver result should include investor {string}") do |investor_name|
  names = @resolver_result[:investor_rows].map { |r| r[:investor].investor_name }
  expect(names).to include(investor_name)
end

# Verifies the resolver result does NOT include the named investor.
Then("the resolver result should not include investor {string}") do |investor_name|
  names = @resolver_result[:investor_rows].map { |r| r[:investor].investor_name }
  expect(names).not_to include(investor_name)
end

# Verifies the investor-level status for the named investor.
Then("the investor {string} status should be {string}") do |investor_name, status|
  row = @resolver_result[:investor_rows].find { |r| r[:investor].investor_name == investor_name }
  expect(row).to be_present, "Investor #{investor_name} not found in resolver result"
  expect(row[:status]).to eq(status)
end

# Verifies resolver counter values.
Then("the resolver counters should show pending {int}") do |count|
  expect(@resolver_result[:counters][:pending]).to eq(count)
end

Then("the resolver counters should show accepted {int}") do |count|
  expect(@resolver_result[:counters][:accepted]).to eq(count)
end

Then("the resolver counters should show declined {int}") do |count|
  expect(@resolver_result[:counters][:declined]).to eq(count)
end

Then("the resolver counters should show exempt {int}") do |count|
  expect(@resolver_result[:counters][:exempt]).to eq(count)
end

# ── Action steps — NdaSignatory ──────────────────────────────────────────────

# GP tags the LP user as an NDA signatory for the current NDA config.
When("the GP tags the LP user as an NDA signatory") do
  @nda_signatory = NdaSignatory.create!(
    nda_config: @nda_config,
    user: @lp_user,
    tagged_by: @user
  )
end

# Tags the LP user as a signatory — used by resolver scenarios where the investor
# setup step already created the LP user and investor access.
# @note Uses find_or_create_by! because the auto-tag callback on InvestorAccess
#   approval may have already created this signatory record.
Given("the LP user is tagged as a signatory for the NDA") do
  NdaSignatory.find_or_create_by!(
    nda_config: @nda_config,
    user: @lp_user
  ) do |s|
    s.tagged_by = @user
  end
end

# ── Assertion steps — NdaSignatory ──────────────────────────────────────────

# Verifies an NdaSignatory record exists for the LP user.
Then("an NDA signatory record should exist for the LP user") do
  record = NdaSignatory.find_by(nda_config: @nda_config, user: @lp_user)
  expect(record).to be_present
end

# Verifies the tagged_by is the GP user.
Then("the NDA signatory tagged_by should be the GP user") do
  expect(@nda_signatory.tagged_by).to eq(@user)
end

# Attempts to create a duplicate signatory; expects validation error.
Then("creating a duplicate NDA signatory for the LP user should raise an error") do
  expect do
    NdaSignatory.create!(
      nda_config: @nda_config,
      user: @lp_user,
      tagged_by: @user
    )
  end.to raise_error(ActiveRecord::RecordInvalid)
end

# Verifies signatory count for the LP user.
Then("there should be {int} NDA signatories for the LP user") do |count|
  records = NdaSignatory.where(user: @lp_user)
  expect(records.count).to eq(count)
end

# Verifies the LP user is marked as nda_tagged in the resolver user rows.
Then("the LP user should be marked as nda_tagged in the resolver result") do
  user_row = @resolver_result[:investor_rows]
    .flat_map { |r| r[:users] }
    .find { |u| u[:user].id == @lp_user.id }
  expect(user_row).to be_present, "LP user not found in resolver result"
  expect(user_row[:nda_tagged]).to be true
end

# Verifies the LP user is NOT marked as nda_tagged in the resolver user rows.
Then("the LP user should not be marked as nda_tagged in the resolver result") do
  user_row = @resolver_result[:investor_rows]
    .flat_map { |r| r[:users] }
    .find { |u| u[:user].id == @lp_user.id }
  expect(user_row).to be_present, "LP user not found in resolver result"
  expect(user_row[:nda_tagged]).to be false
end

# Creates a second LP user under the same investor. Auto-tag only picks the
# oldest approved user, so this user will not be a signatory.
Given("there is a second LP user for {string}") do |_investor_name|
  @lp_user_2 = User.create!(
    email: "lp_test2_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "LP2",
    last_name: "User"
  )
  InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor,
    user: @lp_user_2,
    email: @lp_user_2.email,
    first_name: @lp_user_2.first_name,
    last_name: @lp_user_2.last_name,
    approved: true
  )
end

# Verifies the second LP user is NOT marked as nda_tagged in the resolver result.
Then("the second LP user should not be marked as nda_tagged in the resolver result") do
  user_row = @resolver_result[:investor_rows]
    .flat_map { |r| r[:users] }
    .find { |u| u[:user].id == @lp_user_2.id }
  expect(user_row).to be_present, "Second LP user not found in resolver result"
  expect(user_row[:nda_tagged]).to be false
end

# ── Assertion steps — Gate exemption check ───────────────────────────────────

# Changed: Gate checks InvestorAccess.exempt_from_nda instead of NdaExemption.
# Why: Stakeholder-level exemption — matches ensure_nda_accepted in DocumentsController.

# Verifies the NDA gate exemption check passes for the LP user.
Then("the NDA gate exemption check should pass for the LP user") do
  result = InvestorAccess.exists?(
    user_id: @lp_user.id,
    entity_id: @nda_config.entity_id,
    approved: true,
    exempt_from_nda: true
  )
  expect(result).to be true
end

# Verifies the NDA gate exemption check does NOT pass for the LP user.
Then("the NDA gate exemption check should not pass for the LP user") do
  result = InvestorAccess.exists?(
    user_id: @lp_user.id,
    entity_id: @nda_config.entity_id,
    approved: true,
    exempt_from_nda: true
  )
  expect(result).to be false
end

# ── Assertion steps — NdaStatusPolicy ────────────────────────────────────────

# Verifies the NDA status policy allows the given action for the GP user.
Then("the NDA status policy should allow {word} for the GP user") do |action|
  policy = NdaStatusPolicy.new(@user, @nda_config)
  expect(policy.public_send("#{action}?")).to be true
end

# Verifies the NDA status policy denies the given action for the LP user.
Then("the NDA status policy should deny {word} for the LP user") do |action|
  policy = NdaStatusPolicy.new(@lp_user, @nda_config)
  expect(policy.public_send("#{action}?")).to be false
end

# Verifies the NDA status policy denies the given action for another GP user.
Then("the NDA status policy should deny {word} for the other GP user") do |action|
  policy = NdaStatusPolicy.new(@other_gp_user, @nda_config)
  expect(policy.public_send("#{action}?")).to be false
end
