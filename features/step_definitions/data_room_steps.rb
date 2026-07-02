# Step definitions for features/core/data_rooms.feature

# ── GP Entity setup ─────────────────────────────────────────────────────────

# Creates the "Data Room" folder as a child of the GP entity's root_folder.
# entity.data_room_folder queries root_folder.children.where(name: "Data Room", level: 1),
# so the folder must be a level-1 child with that exact name.
# Saves @gp_entity as a stable reference because subsequent steps overwrite @entity.
Given('the GP entity has a data room folder') do
  @gp_entity = @entity
  root = @gp_entity.root_folder
  # root_folder is created by SetupCompany when the entity is first saved,
  # but guard defensively in case the test DB has no root yet.
  if root.nil?
    root = Folder.create!(name: "/", entity: @gp_entity, level: 0, folder_type: :system)
    @gp_entity.update_column(:root_folder_id, root.id)
    @gp_entity.reload
  end
  @data_room_folder = root.children.find_or_create_by!(name: "Data Room", entity: @gp_entity, folder_type: :regular)
  puts "\n####Data Room Folder####\n"
  puts @data_room_folder.to_json
end

# Sets the GP entity's domain attribute so that Capybara requests to "localhost"
# resolve @current_entity to it in set_current_entity.
# (set_current_entity falls through to Entity.where(domain: request.domain) when the
# request host doesn't match BASE_DOMAIN, which is the case on localhost in tests.)
Given('the GP entity domain is set to {string}') do |domain|
  @gp_entity ||= @entity
  @gp_entity.update_column(:domain, domain)
  puts "\n####GP Entity domain set to #{domain}####\n"
end

# Creates a second GP entity with enable_data_rooms and a data_room_folder but
# NO Investor or InvestorAccess relationship to the LP — it must never appear
# in the LP's data_rooms listing.
Given('there is a different GP entity with {string} that the LP is not invested in') do |permission|
  @other_gp_entity = FactoryBot.create(:entity, entity_type: "Investment Fund", enable_funds: true)
  @other_gp_entity.permissions.set(permission.to_sym)
  @other_gp_entity.save!
  # Create the Data Room folder so the entity passes the data_room_folder? guard in the view
  other_root = @other_gp_entity.root_folder
  if other_root.nil?
    other_root = Folder.create!(name: "/", entity: @other_gp_entity, level: 0, folder_type: :system)
    @other_gp_entity.update_column(:root_folder_id, other_root.id)
    @other_gp_entity.reload
  end
  other_root.children.find_or_create_by!(name: "Data Room", entity: @other_gp_entity, folder_type: :regular)
  puts "\n####Other GP Entity (no LP access)####\n"
  puts @other_gp_entity.to_json
end

# ── Sub-folder access setup ──────────────────────────────────────────────────

# Creates two sub-folders under the data_room_folder so each can be tested independently.
Given('the data room has sub-folders {string} and {string}') do |accessible_name, restricted_name|
  @gp_entity ||= @entity
  @accessible_folder = @data_room_folder.children.create!(name: accessible_name, entity: @gp_entity)
  @restricted_folder = @data_room_folder.children.create!(name: restricted_name, entity: @gp_entity)
  puts "\n####Sub-folders created: #{accessible_name}, #{restricted_name}####\n"
end

# Creates an AccessRight on the named sub-folder scoped to the LP investor.
# Folder.for_investor joins access_rights and requires a matching record for the user's
# investor/entity combination — without this the folder is invisible to the LP.
Given('the LP investor has been given explicit access to the sub-folder {string}') do |_folder_name|
  @gp_entity ||= @entity
  ar = AccessRight.create!(
    owner: @accessible_folder,
    entity_id: @gp_entity.id,
    access_to_investor_id: @investor.id,
    cascade: false
  )
  puts "\n####AccessRight on Accessible Folder####\n"
  puts ar.to_json
end

# ── Navigation steps ─────────────────────────────────────────────────────────

When('I visit the investor dashboard') do
  visit root_path
end

When('I visit the data rooms listing page') do
  visit data_rooms_folders_path
end

# ── Model-level assertions ────────────────────────────────────────────────────

Then('the GP entity should have a data_room_folder present') do
  @gp_entity.reload
  expect(@gp_entity.data_room_folder).to be_present
end

Then('the GP entity should have enable_data_rooms enabled') do
  @gp_entity.reload
  expect(@gp_entity.permissions.enable_data_rooms?).to be true
end

# ── Dashboard card assertions ────────────────────────────────────────────────

# "Shared Docs" is the subtitle of the Data Rooms card in _vc_dashboard_menus.html.erb.
# Its presence confirms the entire card rendered — the link text alone could be a heading elsewhere.
Then('I should see the Data Rooms card on the dashboard') do
  expect(page).to have_content("Data Rooms")
  expect(page).to have_content("Shared Docs")
end

Then('I should not see the Data Rooms card on the dashboard') do
  expect(page).not_to have_content("Shared Docs")
end

# ── Data rooms listing assertions ─────────────────────────────────────────────

Then('I should see the GP entity in the data rooms list') do
  @gp_entity ||= @entity
  expect(page).to have_content(@gp_entity.name)
end

Then('I should not see the other GP entity in the data rooms list') do
  expect(@other_gp_entity).to be_present, "expected @other_gp_entity to be set by the setup step"
  expect(page).not_to have_content(@other_gp_entity.name)
end

# ── Sub-folder access assertions (model level via Folder.for_investor) ────────

# Folder.for_investor(user, entity) requires the folder to have an AccessRight
# matching the user's investor record AND an approved InvestorAccess for the user.
# @investor_user was created with InvestorAccess approved: true in "existing investor" step.
Then('the LP investor can access {string} via the for_investor scope') do |_folder_name|
  @gp_entity ||= @entity
  accessible = Folder.for_investor(@investor_user, @gp_entity)
  expect(accessible).to include(@accessible_folder),
    "expected Folder.for_investor to include '#{@accessible_folder.name}' " \
    "but got: #{accessible.pluck(:name).inspect}"
end

Then('the LP investor cannot access {string} via the for_investor scope') do |_folder_name|
  @gp_entity ||= @entity
  accessible = Folder.for_investor(@investor_user, @gp_entity)
  expect(accessible).not_to include(@restricted_folder),
    "expected Folder.for_investor to exclude '#{@restricted_folder.name}' " \
    "but it was returned — check AccessRight setup"
end
