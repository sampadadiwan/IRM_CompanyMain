# Steps for features/core/documents_widget.feature (fix-portfolio-dashboard-widgets: Documents widget Folder ID).
# Worked examples: openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples

Given('the entity has a folder {string} outside the company folder with the document {string}') do |folder_name, document_name|
  folder = FactoryBot.create(:folder, entity: @entity, parent: @entity.root_folder, name: folder_name)
  Document.create!(entity_id: @entity.id, name: document_name, user: @user, folder:, file: File.new("public/sample_uploads/SignedDoc.pdf", "r"))
  @documents_folder = folder
end

Given('another entity has a folder {string} with the document {string}') do |folder_name, document_name|
  other = FactoryBot.create(:entity)
  other_user = FactoryBot.create(:user, entity: other)
  folder = FactoryBot.create(:folder, entity: other, parent: other.root_folder, name: folder_name)
  Document.create!(entity_id: other.id, name: document_name, user: other_user, folder:, file: File.new("public/sample_uploads/SignedDoc.pdf", "r"))
  @documents_folder = folder
end

Given('the portfolio company has a user who is signed in as an investor') do
  company_entity = @portfolio_company.investor_entity
  @widget_viewer = FactoryBot.create(:user, entity: company_entity)
  FactoryBot.create(:investor_access, entity: @entity, investor: @portfolio_company, user: @widget_viewer,
                                      email: @widget_viewer.email, approved: true)
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(@widget_viewer, scope: :user)
end

Given('an employee of the entity who is not a company admin is signed in') do
  @widget_viewer = FactoryBot.create(:user, entity: @entity)
  @widget_viewer.remove_role(:company_admin)
  @widget_viewer.extended_permissions.set(:investor_read)
  @widget_viewer.save!
  Warden.test_mode!
  Object.new.extend(Warden::Test::Helpers).login_as(@widget_viewer, scope: :user)
end

Given('that folder and its documents are shared with the portfolio company') do
  [@documents_folder, *@documents_folder.documents].each do |owner|
    AccessRight.create!(owner:, entity_id: @entity.id, access_to_investor_id: @portfolio_company.id, cascade: false)
  end
end

Given('the company dashboard has a Documents widget for that folder') do
  DashboardWidget.create!(entity_id: (@widget_viewer || @user).entity_id, dashboard_name: PORTCO_DASHBOARD, name: "Default", widget_name: "Documents",
                          size: "XL", position: 3, tags: "Docs", display_name: true, enabled: true, show_menu: false,
                          metadata: "{folder_id: #{@documents_folder.id}}")
end

# The widget is the folder tree: choosing the folder lists its documents (as it does on the Documents page)
When('I choose the folder {string} in the Documents widget') do |folder_name|
  within("#documents_3") { find("a", text: folder_name, match: :first).click }
end

Then('the Documents widget should list {string}') do |name|
  expect(find("#documents_3")).to have_content(name)
end

Then('the Documents widget should list no documents and not name the folder {string}') do |folder_name|
  expect(find("#documents_3")).to have_content("No documents to show.")
  expect(find("#documents_3")).to have_no_content("Beta Secret")
  expect(find("#documents_3")).to have_no_content("Board Pack")
  expect(find("#documents_3")).to have_no_content(folder_name)
end
