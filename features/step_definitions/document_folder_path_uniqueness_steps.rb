# Steps for features/core/document_folder_path_uniqueness.feature
#
# Model-level only (no browser): folder creation hangs off WithFolder's lazy
# #document_folder reader and the rename off UpdateDocumentFolderPathJob, so building the
# records and calling the job directly is the whole trigger. Entity/investor setup reuses the
# shared steps in access_rights_cache_steps.rb.

module DocumentFolderPathHelpers
  # The KYC as the database has it. Steps deliberately work off fresh instances, because half
  # the bug was about in-memory attributes leaking into folder names.
  def reloaded_kyc
    InvestorKyc.find(@investor_kyc.id)
  end

  # Folders that could serve as the KYC's document folder: direct children of its KYC-<id>
  # parent that name the KYC as owner. Deliberately not "every folder owned by this KYC" --
  # anything created under the document folder inherits its owner via
  # Folder#set_parent_permissions, so that count would include child folders too.
  def kyc_document_folder_candidates
    kyc = reloaded_kyc
    parent_path = kyc.folder_path.split("/")[0...-1].join("/")
    parent = Folder.find_by(entity_id: @entity.id, full_path: parent_path)
    return Folder.none if parent.nil?

    parent.children.where(owner_id: kyc.id, owner_type: "InvestorKyc")
  end

  # "/Investors/LP Alpha/KYC-<id>/Alpha Trust II" -- the feature writes <id> rather than
  # hard-coding an autoincrement value.
  def expand_kyc_id(path)
    path.sub("<id>", @investor_kyc.id.to_s)
  end

  def sample_upload
    File.new("public/sample_uploads/GrantLetter.docx", "r")
  end

  # Documents need an author; only the document scenarios pay for one.
  def document_user
    @document_user ||= FactoryBot.create(:user, entity: @entity, first_name: "Folder", last_name: "Tester")
  end

  def create_document(name, folder)
    Document.create!(entity: @entity, name:, user: document_user, folder:, file: sample_upload)
  end
end
World(DocumentFolderPathHelpers)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

# "the entity has a root folder" is not defined here on purpose -- report_builder_steps.rb
# already owns it, and a second definition makes every use of it ambiguous.

Given('there is a KYC {string} for the investor {string}') do |kv, investor_name|
  investor = Investor.find_by!(investor_name:)
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor:, kyc_type: "Non Individual")
  key_values(@investor_kyc, kv)
  @investor_kyc.save!
  # The folder is created lazily on first read, exactly as a controller would trigger it.
  @investor_kyc.document_folder
  @investor_kyc.reload
end

# The shape that started the incident: saved past its own validations, so a plain `save`
# inside setup_document_folder cannot succeed.
Given('there is an incomplete KYC for the investor {string}') do |investor_name|
  investor = Investor.find_by!(investor_name:)
  @investor_kyc = InvestorKyc.new(entity: @entity, investor:, kyc_type: "Non Individual")
  @investor_kyc.save(validate: false)
  @investor_kyc.reload
end

Given('the KYC document folder has a child folder {string}') do |name|
  @child_folder = Folder.create!(name:, parent: reloaded_kyc.document_folder, entity: @entity)
end

Given('the KYC document folder link is cleared') do
  # Legacy data: the Folder row exists and knows its owner, the owner does not know the folder.
  @investor_kyc.update_column(:document_folder_id, nil)
  @investor_kyc.reload
end

Given('the KYC is renamed in the database to {string}') do |name|
  # update_column: no callbacks, so no rename job -- this is the "someone renamed it while the
  # link was missing" state, not a live rename.
  @investor_kyc.update_column(:full_name, name)
  @investor_kyc.reload
end

Given('I type {string} into the KYC full name without saving') do |name|
  @investor_kyc = reloaded_kyc
  @investor_kyc.full_name = name
end

Given('the KYC has a stray duplicate folder named {string}') do |name|
  # A second folder under the same parent, owned by the same KYC: what step 2 of the chain
  # used to leave behind. owner is set explicitly because set_parent_permissions would
  # otherwise inherit the parent's owner (the Investor).
  parent = reloaded_kyc.document_folder.parent
  @stray_folder = Folder.create!(name:, parent:, entity: @entity, owner: reloaded_kyc)
end

Given('the stray duplicate folder has a document {string}') do |name|
  @stray_document_name = name
  create_document(name, @stray_folder)
end

Given('the stray duplicate folder has a child folder {string}') do |name|
  @stray_child_folder = Folder.create!(name:, parent: @stray_folder, entity: @entity)
end

Given("the document {string} is in the stray duplicate's child folder {string}") do |doc_name, folder_name|
  folder = @stray_folder.children.find_by!(name: folder_name)
  create_document(doc_name, folder)
end

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

When('I rename the KYC to {string}') do |name|
  reloaded_kyc.update!(full_name: name)
  @investor_kyc.reload
end

When('the KYC document folder is set up') do
  @investor_kyc.document_folder
end

When('the KYC document folder is set up again from a fresh instance') do
  # A later request: same row, new object, no memory of the first pass.
  InvestorKyc.find(@investor_kyc.id).document_folder
end

When('the folder path job runs for the KYC') do
  kyc = reloaded_kyc
  @folder_job_error = nil
  begin
    UpdateDocumentFolderPathJob.perform_now(kyc.class.name, kyc.id)
  rescue StandardError => e
    @folder_job_error = e
  end
  @investor_kyc.reload
end

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

Then('the KYC should have exactly {int} document folder') do |count|
  expect(kyc_document_folder_candidates.count).to eq(count)
end

Then('the KYC should not be valid') do
  expect(reloaded_kyc).not_to be_valid
end

Then('the KYC document_folder_id should be persisted') do
  expect(reloaded_kyc.read_attribute(:document_folder_id)).to be_present
end

Then('the KYC document folder should be at its expected path') do
  kyc = reloaded_kyc
  expect(kyc.document_folder.full_path).to eq(kyc.folder_path)
end

Then('the KYC document folder should be named {string}') do |name|
  expect(reloaded_kyc.document_folder.name).to eq(name)
end

Then('the KYC document folder should be owned by the KYC') do
  kyc = reloaded_kyc
  expect(kyc.document_folder.owner_id).to eq(kyc.id)
  expect(kyc.document_folder.owner_type).to eq("InvestorKyc")
end

Then('the child folder {string} should be at path {string}') do |name, path|
  folder = Folder.find_by!(name:, entity: @entity)
  expect(folder.full_path).to eq(expand_kyc_id(path))
end

Then('no folder should be named {string}') do |name|
  expect(Folder.where(entity: @entity, name:)).to be_none
end

Then('the folder path job should not have raised') do
  expect(@folder_job_error).to be_nil
end

Then('the document {string} should be in the KYC document folder') do |name|
  document = Document.find_by!(name:, entity: @entity)
  expect(document.folder_id).to eq(reloaded_kyc.document_folder_id)
end

Then('the child folder {string} should be under the KYC document folder') do |name|
  folder = Folder.find_by!(name:, entity: @entity)
  expect(folder.parent_id).to eq(reloaded_kyc.document_folder_id)
  expect(folder.full_path).to eq("#{reloaded_kyc.document_folder.full_path}/#{name}")
end

Then('the KYC document folder should have exactly {int} child folder named {string}') do |count, name|
  expect(reloaded_kyc.document_folder.children.where(name:).count).to eq(count)
end

Then('the document {string} should be in the child folder {string}') do |doc_name, folder_name|
  document = Document.find_by!(name: doc_name, entity: @entity)
  folder = reloaded_kyc.document_folder.children.find_by!(name: folder_name)
  expect(document.folder_id).to eq(folder.id)
end

Then('UpdateDocumentFolderPathJob should discard ActiveRecord::RecordInvalid') do
  # rescue_with_handler returns the handler's result (truthy) when the exception is handled
  # by discard_on/retry_on, and nil when nothing claims it -- i.e. when it would bubble up to
  # Sidekiq and burn the full retry budget, one error email per attempt.
  handled = UpdateDocumentFolderPathJob.new.rescue_with_handler(
    ActiveRecord::RecordInvalid.new(Folder.new)
  )
  expect(handled).not_to be_nil
end
