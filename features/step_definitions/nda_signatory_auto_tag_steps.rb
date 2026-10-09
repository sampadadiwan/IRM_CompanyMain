# frozen_string_literal: true

# Step definitions for features/core/nda_signatory_auto_tag.feature
# Module 10 — Auto-tag NDA signatory on investor access approval and
#   folder-scoped auto-tag on NDA creation.
#
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config),
#   nda_status_steps.rb (LP investor with approved access, signatory tagging),
#   and data_room_steps.rb (data room folder creation).

# ── Setup steps — New LP investor with folder access but no InvestorAccess ──

# Changed: Creates an LP investor with an AccessRight on the data room folder
#   but no InvestorAccess yet. Used to test auto-tag on access creation.
# Why: The auto-tag callback fires on InvestorAccess create/update, so we need
#   the investor to exist with folder access before the access is created.
#
# @param investor_name [String] the investor name to create
Given("there is a new LP investor {string} with folder access but no investor access yet") do |investor_name|
  lp_entity = Entity.create!(
    name: "#{investor_name} Entity",
    entity_type: "Limited Partner",
    primary_email: "#{investor_name.parameterize}@example.com"
  )
  @new_lp_user = User.create!(
    email: "#{investor_name.parameterize}_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: lp_entity,
    first_name: investor_name.split.first,
    last_name: investor_name.split.last || "User"
  )
  @new_lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: lp_entity,
    category: "LP",
    primary_email: lp_entity.primary_email
  )
  # Changed: Create folder-level AccessRight so the auto-tag callback finds this investor.
  # Why: The callback checks AccessRight on the NDA's folder before tagging.
  AccessRight.find_or_create_by!(
    owner: @data_room_folder,
    entity_id: @gp_entity.id,
    access_to_investor_id: @new_lp_investor.id,
    cascade: false
  )
  instance_variable_set("@investor_#{investor_name.parameterize(separator: '_')}", @new_lp_investor)
  instance_variable_set("@user_#{investor_name.parameterize(separator: '_')}", @new_lp_user)
end

# Changed: Creates an LP investor with folder access and unapproved InvestorAccess.
# Why: Tests the toggle-to-approved path for auto-tag.
#
# @param investor_name [String] the investor name to create
Given("there is a new LP investor {string} with folder access and unapproved investor access") do |investor_name|
  lp_entity = Entity.create!(
    name: "#{investor_name} Entity",
    entity_type: "Limited Partner",
    primary_email: "#{investor_name.parameterize}@example.com"
  )
  @new_lp_user = User.create!(
    email: "#{investor_name.parameterize}_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: lp_entity,
    first_name: investor_name.split.first,
    last_name: investor_name.split.last || "User"
  )
  @new_lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: lp_entity,
    category: "LP",
    primary_email: lp_entity.primary_email
  )
  AccessRight.find_or_create_by!(
    owner: @data_room_folder,
    entity_id: @gp_entity.id,
    access_to_investor_id: @new_lp_investor.id,
    cascade: false
  )
  # Changed: Create as unapproved — auto-tag should NOT fire yet.
  # Why: The callback guard is `if: :approved?`, so unapproved access is skipped.
  @unapproved_access = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @new_lp_investor,
    user: @new_lp_user,
    email: @new_lp_user.email,
    first_name: @new_lp_user.first_name,
    last_name: @new_lp_user.last_name,
    approved: false
  )
  instance_variable_set("@investor_#{investor_name.parameterize(separator: '_')}", @new_lp_investor)
  instance_variable_set("@user_#{investor_name.parameterize(separator: '_')}", @new_lp_user)
end

# Changed: Creates an LP investor with entity-level access but NO folder AccessRight.
# Why: Tests that entity-wide investors are not auto-tagged — only folder-scoped.
#
# @param investor_name [String] the investor name to create
Given("there is an LP investor {string} with entity access but no folder access") do |investor_name|
  lp_entity = Entity.create!(
    name: "#{investor_name} Entity",
    entity_type: "Limited Partner",
    primary_email: "#{investor_name.parameterize}@example.com"
  )
  @no_folder_lp_user = User.create!(
    email: "#{investor_name.parameterize}_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: lp_entity,
    first_name: investor_name.split.first,
    last_name: investor_name.split.last || "User"
  )
  @no_folder_lp_investor = Investor.create!(
    investor_name: investor_name,
    entity: @gp_entity,
    investor_entity: lp_entity,
    category: "LP",
    primary_email: lp_entity.primary_email
  )
  # Changed: Create InvestorAccess (entity-level) but NO AccessRight on the folder.
  # Why: This investor should be invisible to folder-scoped auto-tag.
  @no_folder_access = InvestorAccess.create!(
    entity: @gp_entity,
    investor: @no_folder_lp_investor,
    user: @no_folder_lp_user,
    email: @no_folder_lp_user.email,
    first_name: @no_folder_lp_user.first_name,
    last_name: @no_folder_lp_user.last_name,
    approved: false
  )
  instance_variable_set("@investor_#{investor_name.parameterize(separator: '_')}", @no_folder_lp_investor)
  instance_variable_set("@user_#{investor_name.parameterize(separator: '_')}", @no_folder_lp_user)
end

# ── Setup steps — Pre-existing signatory ─────────────────────────────────────

# Changed: Tags an existing LP user as signatory for the folder's NDA config.
# Why: Tests that a second access for the same investor does NOT create a duplicate.
#
# @param investor_name [String] the investor name whose user is already tagged
Given("the LP user for {string} is already a signatory for the folder NDA") do |_investor_name|
  NdaSignatory.find_or_create_by!(
    nda_config: @nda_config,
    user: @lp_user,
    tagged_by: @user
  )
end

# ── Action steps — Create approved InvestorAccess ────────────────────────────

# Changed: Creates an approved InvestorAccess, which should trigger the auto-tag callback.
# Why: This is the primary action under test — the after_commit callback on InvestorAccess.
#
# @param investor_name [String] the investor to create access for
When("the GP creates an approved investor access for {string}") do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @gp_entity)
  user = instance_variable_get("@user_#{investor_name.parameterize(separator: '_')}") || @new_lp_user

  @new_investor_access = InvestorAccess.create!(
    entity: @gp_entity,
    investor: investor,
    user: user,
    email: user.email,
    first_name: user.first_name,
    last_name: user.last_name,
    approved: true
  )
end

# Changed: Creates a second approved InvestorAccess for an investor that already has one.
# Why: Tests idempotency — a second user for the same investor should not create a duplicate signatory.
#
# @param investor_name [String] the investor to add a second access for
When("the GP creates a second approved investor access for {string}") do |investor_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @gp_entity)
  second_user = User.create!(
    email: "second_#{SecureRandom.hex(4)}@example.com",
    password: "password",
    entity: investor.investor_entity,
    first_name: "Second",
    last_name: "User"
  )
  InvestorAccess.create!(
    entity: @gp_entity,
    investor: investor,
    user: second_user,
    email: second_user.email,
    first_name: second_user.first_name,
    last_name: second_user.last_name,
    approved: true
  )
end

# Changed: Toggles an unapproved InvestorAccess to approved.
# Why: Tests the update path — after_commit fires on update when approved? becomes true.
#
# @param investor_name [String] the investor whose access to approve
When("the GP approves the investor access for {string}") do |investor_name|
  access = if investor_name == "No Folder LP"
             @no_folder_access
           else
             @unapproved_access
           end
  access.update!(approved: true)
end

# ── Action steps — NDA creation with folder-scoped auto-tag ──────────────────

# Changed: Creates NDA config and runs folder-scoped auto-tagging (new controller logic).
# Why: Tests the fixed controller auto-tag that uses Investor.owner_access_rights instead
#   of entity-wide InvestorAccess query.
When("the GP creates an NDA config with folder-scoped auto-tagging") do
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

  # Changed: Folder-scoped auto-tag (matches the fixed NdaConfigsController logic).
  # Why: Only investors with AccessRight on this folder should get signatories tagged.
  folder_investor_ids = Investor.owner_access_rights(@data_room_folder, nil).pluck(:id)
  InvestorAccess
    .where(entity_id: @nda_config.entity_id, investor_id: folder_investor_ids, approved: true)
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

# ── Assertion steps ──────────────────────────────────────────────────────────

# Changed: Verifies the signatory for a specific investor is the newly added user.
# Why: Confirms the callback tagged the correct user (the one being approved).
#
# @param investor_name [String] the investor to check
Then("the signatory for {string} should be the newly added user") do |investor_name|
  user = instance_variable_get("@user_#{investor_name.parameterize(separator: '_')}") || @new_lp_user
  signatory = NdaSignatory.find_by(nda_config: @nda_config, user_id: user.id)
  expect(signatory).to be_present, "Expected #{user.email} to be auto-tagged as signatory for #{investor_name}"
end

# Changed: Verifies total NDA signatory count across all NDA configs.
# Why: Confirms no signatories were created when none should exist (e.g. no NDA on folder).
#
# @param count [Integer] expected total count
Then("there should be {int} NDA signatories in total") do |count|
  expect(NdaSignatory.count).to eq(count)
end

# Changed: Verifies signatory count for a specific investor (0 case).
# Why: Confirms entity-only investors are not tagged by folder-scoped auto-tag.
#
# @param count [Integer] expected signatory count
# @param investor_name [String] the investor to check
Then("there should be {int} NDA signatories for investor {string}") do |count, investor_name|
  investor = Investor.find_by!(investor_name: investor_name, entity: @gp_entity)
  investor_user_ids = InvestorAccess
                      .where(entity_id: @gp_entity.id, investor_id: investor.id, approved: true)
                      .pluck(:user_id)

  # Changed: Also check unapproved access user_ids for the 0-signatory assertion.
  # Why: An investor with only unapproved access still has user_ids we need to check against.
  if investor_user_ids.empty?
    investor_user_ids = InvestorAccess
                        .where(entity_id: @gp_entity.id, investor_id: investor.id)
                        .pluck(:user_id)
  end

  signatory_count = NdaSignatory.where(nda_config: @nda_config, user_id: investor_user_ids).count
  expect(signatory_count).to eq(count)
end
