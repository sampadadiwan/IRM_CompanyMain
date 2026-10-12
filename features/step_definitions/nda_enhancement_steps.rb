# frozen_string_literal: true

# Step definitions for features/core/nda_enhancements.feature
# Module 9 — Enhancements: auto-tagging default signatories on NDA creation,
#   non-signatory blocked page, gate signatory routing, version history audit,
#   and VALID_REASONS whitelist.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config),
#   nda_status_steps.rb (LP investor with approved access, signatory tagging),
#   and nda_expiry_versioning_steps.rb (version bump, version acceptance).

# ── Setup steps — Multiple Investors ─────────────────────────────────────────

# Creates a second LP investor with approved access (separate from "Acme Capital").
Given("there is a second LP investor {string} with approved access to the GP entity") do |investor_name|
  @lp_entity_2 = Entity.create!(
    name: "LP Entity 2", entity_type: "Limited Partner", primary_email: "lp_entity2@example.com"
  )
  @lp_user_2 = User.create!(
    email: "lp_test2_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity_2,
    first_name: "LP2",
    last_name: "User"
  )
  @lp_investor_2 = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: @lp_entity_2,
    category: "LP",
    primary_email: @lp_entity_2.primary_email
  )
  @lp_investor_access_2 = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor_2,
    user: @lp_user_2,
    email: @lp_user_2.email,
    first_name: @lp_user_2.first_name,
    last_name: @lp_user_2.last_name,
    approved: true
  )
  # Changed: Create folder-level AccessRight for second investor.
  # Why: NdaStatusResolver uses folder-scoped access rights.
  if @data_room_folder
    AccessRight.find_or_create_by!(
      owner: @data_room_folder,
      entity_id: @gp_entity.id,
      access_to_investor_id: @lp_investor_2.id,
      cascade: false
    )
  end
end

# Creates an LP investor with two approved users.
Given("there is an LP investor {string} with two approved users") do |investor_name|
  @lp_entity ||= Entity.create!(
    name: "LP Entity", entity_type: "Limited Partner", primary_email: "lp_entity@example.com"
  )

  @lp_user_oldest = User.create!(
    email: "lp_oldest_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "Oldest",
    last_name: "User"
  )
  @lp_user_newest = User.create!(
    email: "lp_newest_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: @lp_entity,
    first_name: "Newest",
    last_name: "User"
  )

  @lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: @lp_entity,
    category: "LP",
    primary_email: @lp_entity.primary_email
  )

  @lp_investor_access_oldest = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor,
    user: @lp_user_oldest,
    email: @lp_user_oldest.email,
    first_name: @lp_user_oldest.first_name,
    last_name: @lp_user_oldest.last_name,
    approved: true,
    created_at: 2.years.ago
  )

  @lp_investor_access_newest = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @lp_investor,
    user: @lp_user_newest,
    email: @lp_user_newest.email,
    first_name: @lp_user_newest.first_name,
    last_name: @lp_user_newest.last_name,
    approved: true,
    created_at: 1.day.ago
  )

  # Set @lp_user for compatibility with shared steps
  @lp_user = @lp_user_oldest

  # Changed: Create folder-level AccessRight for two-user investor.
  # Why: NdaStatusResolver uses folder-scoped access rights.
  if @data_room_folder
    AccessRight.find_or_create_by!(
      owner: @data_room_folder,
      entity_id: @gp_entity.id,
      access_to_investor_id: @lp_investor.id,
      cascade: false
    )
  end
end

# ── Action steps — Auto-tagging ──────────────────────────────────────────────

# Creates an NDA config and runs auto-tagging (mirrors NdaConfigsController#create).
When("the GP creates an NDA config with auto-tagging") do
  @nda_config = NdaConfig.create!(
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_nda_document,
    validity_type: "until_revoked",
    acceptance_method: "click_through",
    created_by: @user,
    updated_by: @user
  )
  @data_room_folder.update!(nda_inheritance_mode: "own")

  # Auto-tag default signatories (same logic as controller)
  InvestorAccess
    .where(entity_id: @nda_config.entity_id, approved: true)
    .order(:created_at)
    .group_by(&:investor_id)
    .each_value do |accesses|
      oldest = accesses.first
      NdaSignatory.create!(
        nda_config: @nda_config,
        user_id: oldest.user_id,
        tagged_by: @user
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
end

# LP user is already a signatory (pre-existing).
Given("the LP user is already a signatory for the NDA") do
  NdaSignatory.create!(
    nda_config: @nda_config,
    user: @lp_user,
    tagged_by: @user
  )
end

# Runs auto-tagging on an existing NDA config (idempotency test).
When("auto-tagging is run for the NDA config") do
  InvestorAccess
    .where(entity_id: @nda_config.entity_id, approved: true)
    .order(:created_at)
    .group_by(&:investor_id)
    .each_value do |accesses|
      oldest = accesses.first
      NdaSignatory.create!(
        nda_config: @nda_config,
        user_id: oldest.user_id,
        tagged_by: @user
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
end

# ── Assertion steps — Auto-tagging ───────────────────────────────────────────

# Verifies signatory count for a specific investor.
Then("there should be {int} NDA signatory for investor {string}") do |count, investor_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @gp_entity)
  investor_user_ids = InvestorAccess
                      .where(entity_id: @gp_entity.id, investor_id: investor.id, approved: true)
                      .pluck(:user_id)
  signatory_count = NdaSignatory.where(nda_config: @nda_config, user_id: investor_user_ids).count
  expect(signatory_count).to eq(count)
end

# Verifies the auto-tagged signatory is the oldest user.
Then("the auto-tagged signatory for {string} should be the oldest user") do |_investor_name|
  signatory = NdaSignatory.find_by(nda_config: @nda_config, user_id: @lp_user_oldest.id)
  expect(signatory).to be_present, "Expected oldest user to be auto-tagged as signatory"

  newest_signatory = NdaSignatory.find_by(nda_config: @nda_config, user_id: @lp_user_newest.id)
  expect(newest_signatory).to be_nil, "Expected newest user NOT to be auto-tagged"
end

# ── Assertion steps — Signatory Check ────────────────────────────────────────

# Verifies the LP user is NOT a signatory.
Then("the LP user should be identified as a non-signatory for the NDA") do
  is_signatory = NdaSignatory.exists?(nda_config_id: @nda_config.id, user_id: @lp_user.id)
  expect(is_signatory).to be false
end

# Verifies the second LP user is NOT a signatory — auto-tag only picks the oldest
# approved user, so the second user under the same investor is not tagged.
Then("the second LP user should be identified as a non-signatory for the NDA") do
  is_signatory = NdaSignatory.exists?(nda_config_id: @nda_config.id, user_id: @lp_user_2.id)
  expect(is_signatory).to be false
end

# Verifies the LP user IS a signatory.
Then("the LP user should be identified as a signatory for the NDA") do
  is_signatory = NdaSignatory.exists?(nda_config_id: @nda_config.id, user_id: @lp_user.id)
  expect(is_signatory).to be true
end

# ── Assertion steps — Gate Target ────────────────────────────────────────────

# Determines what the gate would do for the LP user, based on signatory status
# and acceptance state. Returns "blocked", "acceptance", or "pass".
Then("the gate target for the LP user should be {string}") do |expected|
  nda_config = @data_room_folder.effective_nda_config
  expect(nda_config).to be_present

  is_signatory = NdaSignatory.exists?(nda_config_id: nda_config.id, user_id: @lp_user.id)

  investor_ids = InvestorAccess
                 .where(user_id: @lp_user.id, entity_id: nda_config.entity_id, approved: true)
                 .pluck(:investor_id)

  latest = NdaAcceptance
           .where(nda_config_id: nda_config.id, investor_id: investor_ids)
           .order(created_at: :desc)
           .first

  target = if latest&.accepted? && latest.nda_version == nda_config.version
             "pass"
           elsif is_signatory
             "acceptance"
           else
             "blocked"
           end

  expect(target).to eq(expected)
end

# Gate target check for the second LP user (non-signatory scenarios).
Then("the gate target for the second LP user should be {string}") do |expected|
  nda_config = @data_room_folder.effective_nda_config
  expect(nda_config).to be_present

  is_signatory = NdaSignatory.exists?(nda_config_id: nda_config.id, user_id: @lp_user_2.id)

  investor_ids = InvestorAccess
                 .where(user_id: @lp_user_2.id, entity_id: nda_config.entity_id, approved: true)
                 .pluck(:investor_id)

  latest = NdaAcceptance
           .where(nda_config_id: nda_config.id, investor_id: investor_ids)
           .order(created_at: :desc)
           .first

  target = if latest&.accepted? && latest.nda_version == nda_config.version
             "pass"
           elsif is_signatory
             "acceptance"
           else
             "blocked"
           end

  expect(target).to eq(expected)
end

# ── Assertion steps — Version History Audit ──────────────────────────────────

# Verifies the version record's nda_document_data matches the NDA config's.
Then("the version record nda_document_data should match the NDA config") do
  record = NdaConfigVersion.find_by!(nda_config: @nda_config, version: 1)
  expect(record.nda_document_data).to eq(@nda_config.nda_document_data)
end

# Verifies duplicate version number is rejected.
# Changed: Use rescue-based check instead of compound raise_error matcher.
# Why: RSpec cannot combine two raise_error matchers with .or because both
#   expect a call stack jump. DB may raise RecordNotUnique or model validation
#   may raise RecordInvalid depending on which check fires first.
Then("creating a duplicate version 1 record should raise an error") do
  error_raised = false
  begin
    NdaConfigVersion.create!(
      nda_config: @nda_config,
      version: 1,
      nda_document_data: fake_shrine_nda_document,
      resign_required: false,
      uploaded_by: @user
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    error_raised = true
  end
  expect(error_raised).to be(true), "Expected duplicate version to raise an error but it did not"
end

# ── Assertion steps — VALID_REASONS ──────────────────────────────────────────

# Verifies VALID_REASONS includes a specific reason.
Then("the NDA acceptance VALID_REASONS should include {string}") do |reason|
  expect(NdaAcceptancesController::VALID_REASONS).to include(reason)
end

# Verifies VALID_REASONS does NOT include a specific reason.
Then("the NDA acceptance VALID_REASONS should not include {string}") do |reason|
  expect(NdaAcceptancesController::VALID_REASONS).not_to include(reason)
end
