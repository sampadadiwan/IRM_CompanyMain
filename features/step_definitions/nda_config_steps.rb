# frozen_string_literal: true

# Step definitions for features/core/nda_config.feature
# Module 1 — NDA Configuration: model-level tests for NdaConfig CRUD,
# validations, Folder#nda_required?, Folder#in_data_room?, and policy checks.
# Changed: FolderNdaConfig → NdaConfig, folder: → owner:, FolderNdaConfigPolicy → NdaConfigPolicy.
# Why: NdaConfig is now polymorphic (belongs_to :owner) per reviewer feedback on PR #1750.

# Builds a fake Shrine JSON hash so NdaConfig passes nda_document validation
# without needing an actual file on disk.
# @return [String] JSON string representing a Shrine-compatible upload hash.
def fake_shrine_nda_document
  {
    id: "test/nda_configs/test_nda.pdf",
    storage: "store",
    metadata: { size: 1024, filename: "test_nda.pdf", mime_type: "application/pdf" }
  }.to_json
end

# ── Setup steps ──────────────────────────────────────────────────────────────

# Creates an enabled NDA config on the data room folder with default settings.
# Uses a fake Shrine JSON hash for nda_document_data to satisfy the PDF validation.
Given("the data room folder has an enabled NDA config") do
  @nda_config = NdaConfig.create!(
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_nda_document,
    validity_type: "until_revoked",
    acceptance_method: "click_through"
  )
  # Changed: Set folder mode to "own" after creating NDA config.
  # Why: Matches controller behavior (NdaConfigsController#create sets mode to "own").
  #   Without this, effective_nda_config returns nil for mode="inherit" folders with no ancestor.
  @data_room_folder.update!(nda_inheritance_mode: "own")
end

# Creates a child folder directly under the data room folder.
Given("there is a child folder {string} in the data room") do |name|
  @folders ||= {}
  @folders[name] = @data_room_folder.children.create!(
    name: name,
    entity: @gp_entity
  )
end

# ── Action steps — Create ────────────────────────────────────────────────────

# Creates an NDA config on the data room folder from a Cucumber data table.
# Handles special values: "future" for validity_date, comma-separated notification_emails.
When("the GP creates an NDA config on the data room folder with:") do |table|
  attrs = table.rows_hash
  config_attrs = {
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: attrs["enabled"] == "true",
    acceptance_method: attrs["acceptance_method"] || "click_through",
    validity_type: attrs["validity_type"] || "until_revoked",
    nda_document_data: fake_shrine_nda_document
  }

  # Optional fields
  config_attrs[:validity_days] = attrs["validity_days"].to_i if attrs["validity_days"]

  if attrs["validity_date"]
    config_attrs[:validity_date] = if attrs["validity_date"] == "future"
                                     30.days.from_now.to_date
                                   elsif attrs["validity_date"] == "past"
                                     30.days.ago.to_date
                                   else
                                     Date.parse(attrs["validity_date"])
                                   end
  end

  config_attrs[:contact_email] = attrs["contact_email"] if attrs["contact_email"]
  config_attrs[:notification_emails] = attrs["notification_emails"] if attrs["notification_emails"]

  @nda_config = NdaConfig.new(config_attrs)

  if @nda_config.valid?
    @nda_config.save!
    # Changed: Set folder's nda_inheritance_mode to "own" after saving config.
    # Why: Mirrors NdaConfigsController#create which sets this on save.
    #   effective_nda_config checks nda_own? so without this, nda_required? returns false.
    @data_room_folder.update!(nda_inheritance_mode: "own")
  else
    @nda_config_errors = @nda_config.errors
  end
end

# Tries to create an NDA config WITHOUT a document (for validation testing).
When("the GP tries to create an NDA config without a document:") do |table|
  attrs = table.rows_hash
  @nda_config = NdaConfig.new(
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: attrs["enabled"] == "true",
    acceptance_method: attrs["acceptance_method"] || "click_through",
    validity_type: attrs["validity_type"] || "until_revoked"
  )
  @nda_config.valid?
  @nda_config_errors = @nda_config.errors
end

# ── Action steps — Update ────────────────────────────────────────────────────

# Updates an existing NDA config from a Cucumber data table.
When("the GP updates the NDA config with:") do |table|
  attrs = table.rows_hash
  update_attrs = {}

  update_attrs[:enabled] = attrs["enabled"] == "true" if attrs.key?("enabled")
  update_attrs[:validity_type] = attrs["validity_type"] if attrs["validity_type"]
  update_attrs[:validity_days] = attrs["validity_days"].to_i if attrs["validity_days"]

  @nda_config.update!(update_attrs)
  @nda_config.reload
end

# ── Assertion steps — NDA config existence ───────────────────────────────────

# Checks that the data room folder has an NDA config.
Then("the data room folder should have an NDA config") do
  @data_room_folder.reload
  expect(@data_room_folder.nda_config).to be_present,
                                          "expected data room folder to have an NDA config but it was nil"
end

# ── Assertion steps — NDA config attributes ──────────────────────────────────

# Checks that the NDA config is enabled.
Then("the NDA config should be enabled") do
  expect(@nda_config.reload.enabled?).to be(true),
                                         "expected NDA config to be enabled but it was disabled"
end

# Checks that the NDA config is not enabled.
Then("the NDA config should not be enabled") do
  expect(@nda_config.reload.enabled?).to be(false),
                                         "expected NDA config to be disabled but it was enabled"
end

# Checks the NDA config acceptance_method value.
Then("the NDA config acceptance_method should be {string}") do |expected|
  expect(@nda_config.reload.acceptance_method).to eq(expected),
                                                  "expected acceptance_method '#{expected}' but got '#{@nda_config.acceptance_method}'"
end

# Checks the NDA config validity_type value.
Then("the NDA config validity_type should be {string}") do |expected|
  expect(@nda_config.reload.validity_type).to eq(expected),
                                              "expected validity_type '#{expected}' but got '#{@nda_config.validity_type}'"
end

# Checks the NDA config validity_days value.
Then("the NDA config validity_days should be {int}") do |expected|
  expect(@nda_config.reload.validity_days).to eq(expected),
                                              "expected validity_days #{expected} but got #{@nda_config.validity_days}"
end

# Checks the NDA config validity_date is in the future.
Then("the NDA config validity_date should be in the future") do
  expect(@nda_config.reload.validity_date).to be > Date.current,
                                              "expected validity_date to be in the future but got #{@nda_config.validity_date}"
end

# Checks the NDA config contact_email value.
Then("the NDA config contact_email should be {string}") do |expected|
  expect(@nda_config.reload.contact_email).to eq(expected),
                                              "expected contact_email '#{expected}' but got '#{@nda_config.contact_email}'"
end

# Checks the NDA config notification_emails contains a specific email.
Then("the NDA config notification_emails should contain {string}") do |email|
  parsed = JSON.parse(@nda_config.reload.notification_emails)
  expect(parsed).to include(email),
                    "expected notification_emails to contain '#{email}' but got #{parsed.inspect}"
end

# Checks the NDA config entity matches the folder entity.
Then("the NDA config entity should match the folder entity") do
  expect(@nda_config.reload.entity_id).to eq(@data_room_folder.entity_id),
                                          "expected entity_id #{@data_room_folder.entity_id} but got #{@nda_config.entity_id}"
end

# ── Assertion steps — Folder methods ─────────────────────────────────────────

# Checks Folder#nda_required? return value.
Then("the data room folder nda_required? should be true") do
  @data_room_folder.reload
  expect(@data_room_folder.nda_required?).to be(true),
                                             "expected nda_required? to be true but got false"
end

Then("the data room folder nda_required? should be false") do
  @data_room_folder.reload
  expect(@data_room_folder.nda_required?).to be(false),
                                             "expected nda_required? to be false but got true"
end

# Checks Folder#in_data_room? for the data room folder itself.
Then("the data room folder in_data_room? should be true") do
  expect(@data_room_folder.in_data_room?).to be(true),
                                             "expected data room folder in_data_room? to be true"
end

# Checks Folder#in_data_room? for a named folder.
Then("the folder {string} in_data_room? should be true") do |name|
  folder = @folders[name]
  raise "Folder '#{name}' not found" unless folder

  expect(folder.in_data_room?).to be(true),
                                  "expected folder '#{name}' in_data_room? to be true"
end

Then("the folder {string} in_data_room? should be false") do |name|
  folder = Folder.find_by!(name: name, entity: @gp_entity)
  expect(folder.in_data_room?).to be(false),
                                  "expected folder '#{name}' in_data_room? to be false"
end

# ── Assertion steps — Validation errors ──────────────────────────────────────

# Checks that the NDA config has a validation error on a specific attribute.
Then("the NDA config should have an error on {string}") do |attribute|
  errors = @nda_config_errors || @nda_config.errors
  expect(errors[attribute.to_sym]).to be_present,
                                      "expected validation error on '#{attribute}' but got none. Errors: #{errors.full_messages.join(', ')}"
end

# ── Assertion steps — Uniqueness constraint ──────────────────────────────────

# Checks that creating a second NDA config on the same folder raises an error.
Then("creating a second NDA config on the data room folder should fail") do
  duplicate = NdaConfig.new(
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_nda_document,
    validity_type: "until_revoked",
    acceptance_method: "click_through"
  )
  expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
end

# ── Assertion steps — Policy ─────────────────────────────────────────────────

# Checks that the policy allows a GP employee on a Data Room folder.
Then("the NDA config policy should allow the GP user on the data room folder") do
  config = @data_room_folder.nda_config || @data_room_folder.build_nda_config
  policy = NdaConfigPolicy.new(@user, config)
  expect(policy.new?).to be(true),
                         "expected policy to allow GP user on data room folder"
end

# Checks that the policy denies on a non-Data-Room folder.
Then("the NDA config policy should deny on the folder {string}") do |name|
  folder = Folder.find_by!(name: name, entity: @gp_entity)
  config = folder.build_nda_config
  policy = NdaConfigPolicy.new(@user, config)
  expect(policy.new?).to be(false),
                         "expected policy to deny on non-Data-Room folder '#{name}'"
end
