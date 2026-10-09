# frozen_string_literal: true

# Step definitions for features/core/nda_inheritance.feature
# Module 5 — NDA Inheritance: model-level tests for inheritance resolution.
#
# Changed: FolderNdaConfig → NdaConfig throughout.
# Why: Module 1 was refactored to polymorphic NdaConfig with owner_type/owner_id.
#
# Note: "there is a child folder {string} in the data room" step is defined in
# nda_config_steps.rb — not duplicated here to avoid Cucumber ambiguity.

# ── Setup steps ──────────────────────────────────────────────────────────────

# Creates an NDA config on the data room folder and sets its mode to "own".
Given("the data room folder has an NDA config") do
  fake_shrine_data = {
    id: "test/nda_configs/test_nda.pdf",
    storage: "store",
    metadata: { size: 1024, filename: "test_nda.pdf", mime_type: "application/pdf" }
  }.to_json

  @data_room_nda_config = NdaConfig.create!(
    owner: @data_room_folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_data,
    validity_type: "until_revoked",
    acceptance_method: "click_through"
  )
  @data_room_folder.update!(nda_inheritance_mode: "own")
end

# Creates a child folder under a named parent folder.
Given("there is a child folder {string} under {string}") do |child_name, parent_name|
  @folders ||= {}
  parent = @folders[parent_name]
  raise "Parent folder '#{parent_name}' not found — create it first" unless parent

  @folders[child_name] = parent.children.create!(
    name: child_name,
    entity: @gp_entity
  )
end

# Creates an NDA config on a named folder and sets its mode to "own".
Given("the folder {string} has its own NDA config") do |name|
  folder = @folders[name]
  raise "Folder '#{name}' not found" unless folder

  fake_shrine_data = {
    id: "test/nda_configs/#{name.parameterize}_nda.pdf",
    storage: "store",
    metadata: { size: 1024, filename: "#{name.parameterize}_nda.pdf", mime_type: "application/pdf" }
  }.to_json

  @folder_configs ||= {}
  @folder_configs[name] = NdaConfig.create!(
    owner: folder,
    entity: @gp_entity,
    enabled: true,
    nda_document_data: fake_shrine_data,
    validity_type: "until_revoked",
    acceptance_method: "click_through"
  )
  folder.update!(nda_inheritance_mode: "own")
end

# Sets a named folder's mode to "opt_out".
Given("the folder {string} is opted out of NDA") do |name|
  folder = @folders[name]
  raise "Folder '#{name}' not found" unless folder

  folder.update!(nda_inheritance_mode: "opt_out")
end

# ── Action steps ─────────────────────────────────────────────────────────────

# Reverts a named folder's mode back to "inherit".
When("the folder {string} reverts to inherit mode") do |name|
  folder = @folders[name]
  raise "Folder '#{name}' not found" unless folder

  folder.update!(nda_inheritance_mode: "inherit")
  folder.reload
end

# ── Assertion steps ──────────────────────────────────────────────────────────

# Checks the nda_inheritance_mode column value.
Then("the folder {string} should have nda_inheritance_mode {string}") do |name, expected_mode|
  folder = if @folders&.key?(name)
             @folders[name]
           else
             Folder.find_by!(name: name, entity: @gp_entity)
           end
  folder.reload
  expect(folder.nda_inheritance_mode).to eq(expected_mode),
                                         "expected folder '#{name}' to have nda_inheritance_mode '#{expected_mode}' " \
                                         "but got '#{folder.nda_inheritance_mode}'"
end

# Checks that effective_nda_config returns the data room's config.
Then("the folder {string} effective_nda_config should be the data room's config") do |name|
  folder = @folders[name].reload
  expect(folder.effective_nda_config).to eq(@data_room_nda_config),
                                         "expected folder '#{name}' effective_nda_config to be the data room's config " \
                                         "(id=#{@data_room_nda_config.id}) but got #{folder.effective_nda_config&.id.inspect}"
end

# Checks that effective_nda_config returns the folder's own config.
Then("the folder {string} effective_nda_config should be its own config") do |name|
  folder = @folders[name].reload
  own_config = @folder_configs[name]
  expect(folder.effective_nda_config).to eq(own_config),
                                         "expected folder '#{name}' effective_nda_config to be its own config " \
                                         "(id=#{own_config.id}) but got #{folder.effective_nda_config&.id.inspect}"
end

# Checks that effective_nda_config returns nil.
Then("the folder {string} effective_nda_config should be nil") do |name|
  folder = if @folders&.key?(name)
             @folders[name]
           else
             Folder.find_by!(name: name, entity: @gp_entity)
           end
  folder.reload
  expect(folder.effective_nda_config).to be_nil,
                                         "expected folder '#{name}' effective_nda_config to be nil " \
                                         "but got config id=#{folder.effective_nda_config&.id}"
end

# Checks that nda_source_folder returns the data room folder.
Then("the folder {string} nda_source_folder should be the data room folder") do |name|
  folder = @folders[name].reload
  expect(folder.nda_source_folder).to eq(@data_room_folder),
                                      "expected folder '#{name}' nda_source_folder to be '#{@data_room_folder.name}' " \
                                      "but got '#{folder.nda_source_folder&.name.inspect}'"
end

# Checks that nda_source_folder returns the folder itself.
Then("the folder {string} nda_source_folder should be itself") do |name|
  folder = @folders[name].reload
  expect(folder.nda_source_folder).to eq(folder),
                                      "expected folder '#{name}' nda_source_folder to be itself " \
                                      "but got '#{folder.nda_source_folder&.name.inspect}'"
end

# Checks that nda_required? returns true.
Then("the folder {string} should require NDA") do |name|
  folder = @folders[name].reload
  expect(folder.nda_required?).to be(true),
                                  "expected folder '#{name}' to require NDA but nda_required? returned false"
end

# Checks that nda_required? returns false.
Then("the folder {string} should not require NDA") do |name|
  folder = if @folders&.key?(name)
             @folders[name]
           else
             Folder.find_by!(name: name, entity: @gp_entity)
           end
  folder.reload
  expect(folder.nda_required?).to be(false),
                                  "expected folder '#{name}' to not require NDA but nda_required? returned true"
end

# ── Resolver verification ────────────────────────────────────────────────────

# Verifies that NdaInheritanceResolver produces the same results as the
# per-folder model methods for all folders in the tree.
Then("the resolver results should match model methods for all folders") do
  tree = @data_room_folder.subtree.includes(:nda_config).arrange
  resolver = NdaInheritanceResolver.new(tree)

  all_folders = @data_room_folder.subtree.includes(:nda_config)
  all_folders.each do |folder|
    resolver_config = resolver.effective_config_for(folder)
    model_config = folder.effective_nda_config

    expect(resolver_config).to eq(model_config),
                               "resolver/model mismatch for '#{folder.name}': " \
                               "resolver=#{resolver_config&.id.inspect}, model=#{model_config&.id.inspect}"

    resolver_source = resolver.source_folder_for(folder)
    model_source = folder.nda_source_folder

    expect(resolver_source).to eq(model_source),
                               "resolver/model source mismatch for '#{folder.name}': " \
                               "resolver=#{resolver_source&.name.inspect}, model=#{model_source&.name.inspect}"
  end
end
