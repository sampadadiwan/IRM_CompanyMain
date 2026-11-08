# Steps for features/core/document_screens.feature - the Documents list (folder path heading, Status
# column, row actions menu), the document show page cards and Approve popup, and the document form
# (tag suggestions, New folder popup, iOS toggles). IDs DS1-DS8 are the scenario comments there.

module DocumentScreensHelpers
  # A document in the child folder ("Quarterly"), by the logged-in user, with a small real file
  def create_child_folder_document(name, tags: nil, **attrs)
    Document.create!(name:, folder: @child_folder, entity_id: @child_folder.entity_id, user: @user,
                     tag_list: tags.presence, file: File.new("public/img/whatsappQR.png", "r"), **attrs)
  end
end
World(DocumentScreensHelpers)

Given('the child folder has a document {string} tagged {string}') do |name, tags|
  @document = create_child_folder_document(name, tags:, download: true)
end

Given('the child folder has a document {string} generated from a template and not yet approved') do |name|
  template = create_child_folder_document("#{name} Template")
  @document = create_child_folder_document(name)
  # As DocGenerator leaves it: generated from the template, tagged Generated, waiting for approval
  # (Document#subject_to_approval?). update_columns so no generation callbacks run.
  template.update_columns(template: true)
  @document.update_columns(from_template_id: template.id, owner_tag: "Generated", approved: false)
  expect(@document.reload.to_be_approved?).to be(true)
end

When('I open the child folder on the documents page') do
  # What clicking the folder in the tree loads (folders/_tree_view: no_folders=true) - the folder's own
  # documents; a bare ?folder_id= lists its sub-folders' documents instead
  visit(folder_documents_path(folder_id: @child_folder.id, no_folders: true))
  expect(page).to have_css("#docs_folder_path", wait: 15)
end

# DS1
Then('the folder path should show the firm name, {string} and {string} as links') do |parent, child|
  within("#docs_folder_path") do
    # The root folder shows the firm's name, not "/"
    expect(page).to have_link(@user.entity.name, href: folder_path(@folder.root))
    expect(page).to have_link(parent, href: folder_path(@folder))
    expect(page).to have_link(child, href: folder_path(@child_folder))
  end
end

# DS2
When('I open the document row actions menu') do
  find("#document_#{@document.id}_actions").click
  expect(page).to have_css("#document_#{@document.id} .dropdown-menu.show", wait: 5)
end

Then('the document row actions menu should offer {string}') do |labels|
  within("#document_#{@document.id} .dropdown-menu.show") do
    labels.split(",").map(&:strip).each { |label| expect(page).to have_css(".dropdown-item", text: label) }
  end
end

When('I choose {string} from the document row actions menu') do |label|
  within("#document_#{@document.id} .dropdown-menu.show") { find(".dropdown-item", text: label).click }
end

Then('I should be on the show page of the document') do
  expect(page).to have_css("#document_header", text: @document.name, wait: 15)
  expect(page).to have_current_path(document_path(@document))
end

# DS3
Then('the document row should show the status {string}') do |status|
  within("#document_#{@document.id}") { expect(page).to have_css(".badge", text: status) }
end

When('I open the show page of the document') do
  visit(document_path(@document))
  expect(page).to have_css("#document_header", wait: 15)
end

When('I click Approve on the document') do
  within("#document_actions") { click_on("Approve") }
end

Then('the approve popup should explain {string}') do |card_title|
  within("#confirmModal") { expect(page).to have_css(".action-summary__title", text: card_title, wait: 5) }
end

Then('the document header should show the status {string}') do |status|
  expect(page).to have_css("#document_header .badge", text: status, wait: 15)
end

Then('the document should be approved') do
  expect(@document.reload.approved).to be(true)
  expect(@document.approved_by_id).to eq(@user.id)
end

# DS4
Then('the show page should have the details card and the {string} card') do |title|
  expect(page).to have_css("#document_details_card")
  expect(page).to have_css("#document_permissions_card", text: title)
end

Then('the {string} card should show {string} as {string}') do |title, setting, value|
  within("#document_permissions_card") do
    expect(page).to have_content(title)
    row = find("li", text: setting, match: :first)
    expect(row).to have_css(".badge", text: value)
  end
end

# DS5
When('I edit the document') do
  visit(edit_document_path(@document))
  expect(page).to have_css("#document_form", wait: 15)
end

Then('the tag suggestions should offer {string}') do |tag|
  expect(page).to have_css("#tag_suggestions button[data-tag='#{tag}']", visible: true)
end

Then('the tag suggestions should not offer {string}') do |tag|
  expect(page).to have_no_css("#tag_suggestions button[data-tag='#{tag}']", visible: true)
end

When('I click the tag suggestion {string}') do |tag|
  find("#tag_suggestions button[data-tag='#{tag}']").click
end

Then('the tags field should read {string}') do |value|
  expect(page).to have_field("document_tag_list", with: value)
end

Then('the tag suggestion {string} should be hidden') do |tag|
  expect(page).to have_no_css("#tag_suggestions button[data-tag='#{tag}']", visible: true)
end

# DS6, DS7
When('I open the new document form from the child folder') do
  visit(folder_documents_path(folder_id: @child_folder.id, no_folders: true))
  find("#doc_actions").click
  click_on("New Document")
  expect(page).to have_css("#document_form", wait: 15)
end

When('I create the folder {string} from the document form') do |name|
  click_on("New folder")
  within("#newFolderModal") do
    expect(page).to have_field("new_folder_name", wait: 5)
    fill_in("new_folder_name", with: name)
    click_on("Create folder")
  end
end

Then('the folder {string} should be created inside the child folder and picked') do |name|
  # The popup closes once folders#create answers; the new folder is then the select's value
  expect(page).to have_no_css("#newFolderModal.show", wait: 15)
  folder = Folder.find_by!(name:, entity_id: @child_folder.entity_id)
  expect(folder.parent_id).to eq(@child_folder.id)
  expect(find("#document_folder_id", visible: :all).value).to eq(folder.id.to_s)
end

Then('the New folder popup should say {string}') do |message|
  within("#newFolderModal") { expect(page).to have_css(".alert-danger", text: message, wait: 5) }
  expect(@child_folder.reload.children).to be_empty
end

# DS8
Then('the eSignatures section should be hidden') do
  expect(page).to have_css("#esign_section", visible: :hidden)
end

Then('the eSignatures section should be visible') do
  expect(page).to have_css("#esign_section", visible: true, wait: 5)
end

When('I turn on the document toggle {string}') do |id|
  toggle_on(id)
end

# DS9
Given('the entity has a fund {string} with a document {string}') do |fund_name, doc_name|
  @user.entity.permissions.set(:enable_funds)
  @user.entity.save!
  @fund = FactoryBot.create(:fund, entity_id: @user.entity_id, name: fund_name)
  # Owned by the fund, so an employee's access to it follows their access to the fund
  @document = Document.create!(name: doc_name, folder: @fund.document_folder, owner: @fund, entity_id: @fund.entity_id,
                               user: @user, file: File.new("public/img/whatsappQR.png", "r"))
end

Given('I am signed in as an employee with view-only access to the fund') do
  # Not a company admin; an access right on the fund with no extra permissions = view only
  @employee = FactoryBot.create(:user, entity: @user.entity)
  AccessRight.create!(owner: @fund, entity_id: @fund.entity_id, user_id: @employee.id, notify: false)
  # Guard: they can see the document but not change or delete it, or the menu assertions prove nothing
  expect(DocumentPolicy.new(@employee, @document).show?).to be(true)
  expect(DocumentPolicy.new(@employee, @document).update?).to be(false)
  expect(DocumentPolicy.new(@employee, @document).destroy?).to be(false)
  log_in(@employee)
end

When("I open the fund's documents folder on the documents page") do
  visit(folder_documents_path(folder_id: @fund.document_folder_id, no_folders: true))
  expect(page).to have_css("#document_#{@document.id}", wait: 15)
end

Then('the document row actions menu should say {string}') do |text|
  within("#document_#{@document.id} .dropdown-menu.show") { expect(page).to have_content(text, wait: 10) }
end

Then('the document row actions menu should not offer {string}') do |labels|
  within("#document_#{@document.id} .dropdown-menu.show") do
    labels.split(",").map(&:strip).each { |label| expect(page).to have_no_css(".dropdown-item", text: label) }
  end
end
