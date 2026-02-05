# ===== Steps for create_from_folder feature =====

Given('a portfolio company {string} exist with category {string}') do |name, category|
  @portfolio_company = FactoryBot.create(:investor,
    name: name,
    category: category,
    entity: @entity
  )
end

Given('the portfolio company has a folder with a document') do
  @folder = FactoryBot.create(:folder, owner: @portfolio_company, entity: @entity)

  @document = FactoryBot.create(:document, folder: @folder, entity: @entity)
  @document.file.attach(
    io: File.open(Rails.root.join('public/sample_uploads/SignedDoc.pdf')),
    filename: 'SignedDoc.pdf',
    content_type: 'application/pdf'
  )
end


When('I visit the documents page for the folder') do
  visit folder_documents_path(folder_id: @folder.id)
end

When('I click {string}') do |button_text|
  click_on button_text
end


Then('an AI portfolio report should be created for {string}') do |company_name|
  @report = AiPortfolioReport.last
  expect(@report).to be_present
  expect(@report.portfolio_company.name).to eq(company_name)
  expect(@report.folder).to eq(@folder)
end
