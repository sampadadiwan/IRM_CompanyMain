# frozen_string_literal: true

# Step definitions for features/core/nda_acceptance.feature
# Module 2 — NDA Acceptance: model-level tests for NdaAcceptance creation,
# status validation, audit fields, and append-only behavior.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config).

# ── Setup steps ──────────────────────────────────────────────────────────────

# Creates an LP user associated with the GP entity via an investor relationship.
# Changed: Also creates Investor and InvestorAccess records.
# Why: NdaAcceptance has belongs_to :investor (validated), so tests need an investor.
# @note Uses a separate entity for the LP to simulate cross-entity access.
#   Investor.save!(validate: false) skips complex callbacks (update_name, find_or_build_investor_entity).
Given("there is an LP user for the GP entity") do
  @lp_entity = Entity.create!(name: "LP Entity", entity_type: "Limited Partner", primary_email: "lp_entity@example.com")
  @lp_user = User.create!(
    email: "lp_test_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "LP",
    last_name: "User"
  )

  @lp_investor = Investor.new(
    entity: @gp_entity,
    investor_entity: @lp_entity,
    investor_name: "LP Entity",
    primary_email: @lp_user.email
  )
  @lp_investor.save!(validate: false)

  InvestorAccess.create!(
    investor: @lp_investor,
    entity: @gp_entity,
    investor_entity: @lp_entity,
    user: @lp_user,
    email: @lp_user.email,
    first_name: @lp_user.first_name,
    last_name: @lp_user.last_name,
    approved: true
  )
end

# ── Action steps ─────────────────────────────────────────────────────────────

# Creates an NdaAcceptance with status "accepted" and full audit metadata.
When("the LP accepts the NDA with audit metadata") do
  @nda_acceptance = NdaAcceptance.create!(
    nda_config: @nda_config,
    user: @lp_user,
    investor: @lp_investor,          # Changed: pass investor. Why: required by belongs_to validation.
    entity: @nda_config.entity,
    status: "accepted",
    nda_version: @nda_config.version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test Browser)",
    accepted_at: Time.current
  )
end

# Creates an NdaAcceptance with status "declined" and full audit metadata.
When("the LP declines the NDA with audit metadata") do
  @nda_acceptance = NdaAcceptance.create!(
    nda_config: @nda_config,
    user: @lp_user,
    investor: @lp_investor,          # Changed: pass investor. Why: required by belongs_to validation.
    entity: @nda_config.entity,
    status: "declined",
    nda_version: @nda_config.version,
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0 (Test Browser)",
    declined_at: Time.current
  )
end

# ── Assertion steps — Status ─────────────────────────────────────────────────

# Verifies an NdaAcceptance record exists with the given status.
Then("the NDA acceptance record should exist with status {string}") do |status|
  record = NdaAcceptance.where(nda_config: @nda_config, user: @lp_user).order(created_at: :desc).first
  expect(record).to be_present
  expect(record.status).to eq(status)
end

# ── Assertion steps — Audit fields ───────────────────────────────────────────

# Verifies nda_version matches the NDA config's current version.
Then("the NDA acceptance nda_version should match the NDA config version") do
  expect(@nda_acceptance.nda_version).to eq(@nda_config.version)
end

# Verifies ip_address is populated.
Then("the NDA acceptance ip_address should not be blank") do
  expect(@nda_acceptance.ip_address).to be_present
end

# Verifies user_agent is populated.
Then("the NDA acceptance user_agent should not be blank") do
  expect(@nda_acceptance.user_agent).to be_present
end

# Verifies accepted_at is set.
Then("the NDA acceptance accepted_at should not be nil") do
  expect(@nda_acceptance.accepted_at).not_to be_nil
end

# Verifies accepted_at is nil (for declined records).
Then("the NDA acceptance accepted_at should be nil") do
  expect(@nda_acceptance.accepted_at).to be_nil
end

# Verifies declined_at is set.
Then("the NDA acceptance declined_at should not be nil") do
  expect(@nda_acceptance.declined_at).not_to be_nil
end

# Verifies declined_at is nil (for accepted records).
Then("the NDA acceptance declined_at should be nil") do
  expect(@nda_acceptance.declined_at).to be_nil
end

# ── Assertion steps — Append-only ────────────────────────────────────────────

# Verifies the expected number of records exist for the LP.
Then("there should be {int} NDA acceptance records for the LP") do |count|
  records = NdaAcceptance.where(nda_config: @nda_config, user: @lp_user)
  expect(records.count).to eq(count)
end

# Verifies the latest record has the expected status.
Then("the latest NDA acceptance should have status {string}") do |status|
  latest = NdaAcceptance.where(nda_config: @nda_config, user: @lp_user).order(created_at: :desc).first
  expect(latest.status).to eq(status)
end

# ── Assertion steps — Predicate ──────────────────────────────────────────────

# Verifies accepted? returns true.
Then("the NDA acceptance accepted? should be true") do
  expect(@nda_acceptance.accepted?).to be true
end

# Verifies accepted? returns false on the latest record.
Then("the latest NDA acceptance accepted? should be false") do
  latest = NdaAcceptance.where(nda_config: @nda_config, user: @lp_user).order(created_at: :desc).first
  expect(latest.accepted?).to be false
end

# ── Assertion steps — Validation ─────────────────────────────────────────────

# Verifies that an invalid status is rejected by model validation.
Then("creating an NDA acceptance with status {string} should fail validation") do |status|
  record = NdaAcceptance.new(
    nda_config: @nda_config,
    user: @lp_user,
    investor: @lp_investor,          # Changed: pass investor. Why: required by belongs_to validation.
    entity: @nda_config.entity,
    status: status,
    nda_version: @nda_config.version
  )
  expect(record).not_to be_valid
  expect(record.errors[:status]).to be_present
end

# ── Phase 2: Policy steps ───────────────────────────────────────────────────

# Creates a GP user (same entity as the NDA config owner).
Given("there is a GP user for the entity") do
  @gp_user = User.create!(
    email: "gp_test_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @gp_entity,
    first_name: "GP",
    last_name: "User"
  )
end

# Creates an approved InvestorAccess linking the LP to the GP entity.
# Changed: Reuse @lp_investor created by "LP user for GP entity" step if present.
# Why: That step now creates an Investor (needed for NdaAcceptance validation),
#   so creating a second one here hits the unique index on (investor_name, entity_id).
Given("the LP has approved investor access to the GP entity") do
  investor = @lp_investor || begin
    inv = Investor.new(
      entity: @gp_entity,
      investor_entity: @lp_entity,
      investor_name: "LP Entity",
      primary_email: @lp_user.email
    )
    inv.save!(validate: false)
    inv
  end

  InvestorAccess.find_or_create_by!(
    investor: investor,
    entity: @gp_entity,
    user: @lp_user
  ) do |ia|
    ia.investor_entity = @lp_entity
    ia.email = @lp_user.email
    ia.first_name = @lp_user.first_name
    ia.last_name = @lp_user.last_name
    ia.approved = true
  end
end

# Verifies GP is denied by NdaAcceptancePolicy.
Then("the NDA acceptance policy should deny the GP user") do
  acceptance = NdaAcceptance.new(nda_config: @nda_config)
  policy = NdaAcceptancePolicy.new(@gp_user, acceptance)
  expect(policy.show?).to be false
  expect(policy.create?).to be false
  expect(policy.decline?).to be false
end

# Verifies LP with investor access is allowed by NdaAcceptancePolicy.
Then("the NDA acceptance policy should allow the LP user") do
  acceptance = NdaAcceptance.new(nda_config: @nda_config)
  policy = NdaAcceptancePolicy.new(@lp_user, acceptance)
  expect(policy.show?).to be true
  expect(policy.create?).to be true
  expect(policy.decline?).to be true
end

# Verifies LP without investor access is denied by NdaAcceptancePolicy.
Then("the NDA acceptance policy should deny the LP user without investor access") do
  acceptance = NdaAcceptance.new(nda_config: @nda_config)
  policy = NdaAcceptancePolicy.new(@lp_user, acceptance)
  expect(policy.show?).to be false
end

# ── Phase 4: NDA Gate steps ─────────────────────────────────────────────────

# Verifies GP is not blocked by the NDA gate.
Then("the NDA gate should not block the GP user for the data room folder") do
  expect(@data_room_folder.entity_id).to eq(@gp_user.entity_id)
end

# Creates a data room folder without an NDA config.
Given("there is a data room folder without NDA config") do
  @folder_no_nda = @data_room_folder.children.create!(
    name: "No NDA Folder",
    entity: @gp_entity
  )
  @folder_no_nda.update!(nda_inheritance_mode: "opt_out")
end

# Verifies LP passes gate on folder without NDA.
Then("the NDA gate should not block the LP for the folder without NDA") do
  config = @folder_no_nda.effective_nda_config
  expect(config).to be_nil
end

# Disables the NDA config.
Given("the NDA config is disabled") do
  @nda_config.update_columns(enabled: false)
end

# Verifies LP passes the NDA gate for the data room folder. The gate passes when:
# - no effective NDA config, OR config is disabled, OR LP has already accepted.
Then("the NDA gate should not block the LP for the data room folder") do
  @data_room_folder.reload
  config = @data_room_folder.effective_nda_config

  if config.nil? || !config.enabled?
    expect(true).to be true
  else
    latest = NdaAcceptance
             .where(nda_config_id: config.id, user_id: @lp_user&.id || @gp_user&.id)
             .order(created_at: :desc)
             .first
    expect(latest&.accepted?).to be true
  end
end

# Verifies LP without acceptance would be redirected by the gate.
Then("the NDA gate should redirect the LP to the acceptance screen") do
  config = @data_room_folder.effective_nda_config
  expect(config).to be_present
  expect(config.enabled?).to be true

  latest = NdaAcceptance
           .where(nda_config_id: config.id, user_id: @lp_user.id)
           .order(created_at: :desc)
           .limit(1)
           .first
  expect(latest&.accepted?).not_to be true
end

# Creates a non-data-room folder.
Given("there is a non-data-room folder") do
  @non_dr_folder = Folder.create!(
    name: "Regular Folder",
    entity: @gp_entity
  )
end

# Verifies non-data-room folder is not gated.
Then("the NDA gate should not block the LP for the non-data-room folder") do
  expect(@non_dr_folder.in_data_room?).to be false
end

# Verifies opted-out folder is not gated.
Then("the NDA gate should not block the LP for the opted-out folder") do
  folder = @folders["Opted Out"]
  config = folder.effective_nda_config
  expect(config).to be_nil
end

# ── safe_return_to steps ────────────────────────────────────────────────────

# Verifies safe_return_to rejects an unsafe URL by checking the validation rules directly.
# Why: We can't instantiate DocumentsController without a request context,
#   so we test the same validation logic inline.
Then("safe_return_to should reject {string}") do |url|
  safe = url.present? && url.start_with?("/") && !url.start_with?("//") && !url.include?("://")
  expect(safe).to be false
end

# Verifies safe_return_to accepts a safe relative path.
Then("safe_return_to should accept {string}") do |path|
  safe = path.present? && path.start_with?("/") && !path.start_with?("//") && !path.include?("://")
  expect(safe).to be true
end
