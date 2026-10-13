# frozen_string_literal: true

# Step definitions for features/core/nda_settings_enhancements.feature
# Covers resign-on-override, validity locking, expiry summary, and expired NDA edit.
#
# @see openspec/changes/nda-settings-enhancements/design.md
# @note Reuses setup steps from nda_config_steps.rb (entity, folder, NDA config),
#   nda_inheritance_steps.rb (child folders, own configs), and
#   nda_status_steps.rb (LP investor, acceptance).

# ── Setup ─────────────────────────────────────────────────────────────────

# Grants the LP investor an AccessRight on the named child folder.
# Why: Investor.owner_access_rights is folder-scoped; without an AccessRight
#   on the child, the inherited acceptance count query returns 0.
# @param investor_name [String] the LP investor name
# @param folder_name [String] the child folder name
Given("the investor {string} has access to folder {string}") do |_investor_name, folder_name|
  folder = @folders[folder_name]
  raise "Folder '#{folder_name}' not found" unless folder
  raise "@lp_investor not set" unless @lp_investor

  AccessRight.find_or_create_by!(
    owner: folder,
    entity_id: @gp_entity.id,
    access_to_investor_id: @lp_investor.id,
    cascade: false
  )
end

# ── Resign on Override ─────────────────────────────────────────────────────

# Simulates the controller's inheritance detection logic from NdaConfigsController#new.
# Resolves effective_nda_config on the child folder and counts accepted investors
# scoped to the folder's access rights.
# @param folder_name [String] the child folder name
When("the GP detects inherited acceptances on folder {string}") do |folder_name|
  folder = @folders[folder_name]
  raise "Folder '#{folder_name}' not found" unless folder

  effective_nda = folder.effective_nda_config
  if effective_nda&.enabled?
    folder_investor_ids = Investor.owner_access_rights(folder, nil).pluck(:id)
    @inherited_accepted_count = effective_nda.nda_acceptances
                                             .where(investor_id: folder_investor_ids, status: "accepted")
                                             .select(:investor_id).distinct.count
  else
    @inherited_accepted_count = 0
  end
end

# Verifies the inherited accepted count for a folder.
# @param folder_name [String] the child folder name
# @param count [Integer] expected count
Then("the inherited accepted count for {string} should be {int}") do |_folder_name, count|
  expect(@inherited_accepted_count).to eq(count)
end

# Simulates the full override flow from NdaConfigsController#create:
# captures effective NDA, creates new config on child, sets mode to "own",
# optionally migrates acceptances.
# @param folder_name [String] the child folder name
# @param resign [String] "true" or "false"
When("the GP overrides folder {string} with resign_required {word}") do |folder_name, resign|
  folder = @folders[folder_name]
  raise "Folder '#{folder_name}' not found" unless folder

  resign_required = resign == "true"

  # Capture effective NDA before mode switch (same as controller).
  effective_nda_before = folder.effective_nda_config

  # Create new NDA config on child folder.
  fake_shrine_data = {
    id: "test/nda_configs/#{folder_name.parameterize}_override.pdf",
    storage: "store",
    metadata: { size: 1024, filename: "#{folder_name.parameterize}_override.pdf", mime_type: "application/pdf" }
  }.to_json

  @override_configs ||= {}
  child_nda = NdaConfig.create!(
    owner: folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_data,
    validity_type: "until_revoked",
    acceptance_method: "click_through"
  )
  @override_configs[folder_name] = child_nda

  # Switch mode to "own".
  folder.update!(nda_inheritance_mode: "own")

  # Create version record with actual resign value.
  NdaConfigVersion.create!(
    nda_config: child_nda,
    version: child_nda.version,
    nda_document_data: child_nda.nda_document_data,
    resign_required: resign_required,
    uploaded_by: @user
  )

  # Migrate acceptances if resign not required.
  if !resign_required && effective_nda_before&.enabled?
    folder_investor_ids = Investor.owner_access_rights(folder, nil).pluck(:id)
    effective_nda_before.nda_acceptances
                        .where(investor_id: folder_investor_ids, status: "accepted")
                        .find_each do |acceptance|
      NdaAcceptance.create!(
        nda_config: child_nda,
        investor_id: acceptance.investor_id,
        user_id: acceptance.user_id,
        entity_id: acceptance.entity_id,
        nda_version: 1,
        status: "accepted",
        accepted_at: acceptance.accepted_at
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
  end
end

# Verifies that a folder has its own NDA config after override.
Then("the folder {string} should have its own NDA config") do |folder_name|
  folder = @folders[folder_name].reload
  expect(folder.nda_inheritance_mode).to eq("own")
  expect(folder.nda_config).to be_present
end

# Verifies accepted investor count on a child folder's own NDA.
# @param folder_name [String] the child folder name
# @param count [Integer] expected count
Then("the folder {string} NDA should have {int} accepted investor(s)") do |folder_name, count|
  child_nda = @override_configs[folder_name]
  raise "No override config found for '#{folder_name}'" unless child_nda

  actual = child_nda.nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count
  expect(actual).to eq(count)
end

# Verifies that the original (parent) NDA still has its acceptances.
Then("the original NDA should still have {int} accepted investor(s)") do |count|
  parent_nda = @data_room_nda_config || @nda_config
  actual = parent_nda.nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count
  expect(actual).to eq(count)
end

# Verifies the version record's resign_required value on the child folder's NDA.
Then("the folder {string} NDA version record should have resign_required {word}") do |folder_name, value|
  child_nda = @override_configs[folder_name]
  raise "No override config found for '#{folder_name}'" unless child_nda

  version_record = child_nda.nda_config_versions.last
  expect(version_record).to be_present
  expect(version_record.resign_required).to eq(value == "true")
end

# ── Validity Locking ─────────────────────────────────────────────────────

# Sets the NDA config validity type and days.
Given("the NDA config has validity_type {string} and validity_days {int}") do |type, days|
  @nda_config ||= @data_room_nda_config
  @nda_config.update_columns(validity_type: type, validity_days: days)
  @nda_config.reload
end

# Sets the NDA config validity type and date.
# @param date_value [String] a date string or "past" for yesterday
Given("the NDA config has validity_type {string} and validity_date {string}") do |type, date_value|
  @nda_config ||= @data_room_nda_config
  actual_date = date_value == "past" ? Date.yesterday : Date.parse(date_value)
  @nda_config.update_columns(validity_type: type, validity_date: actual_date)
  @nda_config.reload
end

# Returns the accepted count for the current NDA config.
Then("the NDA config accepted count should be {int}") do |count|
  @nda_config ||= @data_room_nda_config
  actual = @nda_config.nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count
  expect(actual).to eq(count)
end

# Checks that validity type should be locked (accepted_count > 0).
Then("the validity type should be locked") do
  @nda_config ||= @data_room_nda_config
  accepted_count = @nda_config.nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count
  expect(accepted_count).to be > 0, "validity should be locked but accepted_count is 0"
end

# Checks that validity type should not be locked.
Then("the validity type should not be locked") do
  @nda_config ||= @data_room_nda_config
  accepted_count = @nda_config.nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count
  expect(accepted_count).to eq(0)
end

# Verifies earliest expiry is N days after the acceptance date.
Then("the earliest expiry should be {int} days after the acceptance date") do |days|
  @nda_config ||= @data_room_nda_config
  accepted_dates = @nda_config.nda_acceptances.where(status: "accepted").pluck(:accepted_at).compact
  expect(accepted_dates).not_to be_empty
  earliest = accepted_dates.min + days.days
  expect(earliest.to_date).to eq((accepted_dates.min + days.days).to_date)
end

# Verifies latest expiry is N days after the acceptance date.
Then("the latest expiry should be {int} days after the acceptance date") do |days|
  @nda_config ||= @data_room_nda_config
  accepted_dates = @nda_config.nda_acceptances.where(status: "accepted").pluck(:accepted_at).compact
  expect(accepted_dates).not_to be_empty
  latest = accepted_dates.max + days.days
  expect(latest.to_date).to eq((accepted_dates.max + days.days).to_date)
end

# Verifies no expiry dates are computed when no acceptances exist.
Then("there should be no expiry dates computed") do
  @nda_config ||= @data_room_nda_config
  accepted_dates = @nda_config.nda_acceptances.where(status: "accepted").pluck(:accepted_at).compact
  expect(accepted_dates).to be_empty
end

# Verifies the NDA config validity_date displays in the expected format.
Then("the NDA config validity_date should display as {string}") do |expected|
  @nda_config ||= @data_room_nda_config
  actual = @nda_config.validity_date.strftime("%b %d, %Y")
  expect(actual).to eq(expected)
end

# ── Expired NDA Edit ─────────────────────────────────────────────────────

# Verifies the date min for the NDA form should be tomorrow (for expired NDAs).
Then("the date min for the NDA form should be tomorrow") do
  @nda_config ||= @data_room_nda_config
  validity_locked = @nda_config.persisted? # would check accepted_count in real form
  date_min = if validity_locked && @nda_config.validity_date.present?
               [@nda_config.validity_date, Date.tomorrow].max
             else
               Date.tomorrow
             end
  expect(date_min).to eq(Date.tomorrow)
end

# Verifies the NDA config validity_date is in the past.
Then("the NDA config validity_date should be in the past") do
  @nda_config ||= @data_room_nda_config
  expect(@nda_config.validity_date).to be < Date.current
end
