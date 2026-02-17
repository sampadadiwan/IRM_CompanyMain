# Step definitions for upload_documents_modal.feature

Given('I am at the new AI portfolio report page') do
  visit new_ai_portfolio_report_path
end

When('I select portfolio company {string}') do |company_name|
  select company_name, from: 'ai_portfolio_report_portfolio_company_id'
end

Then('I should see the {string} link') do |link_text|
  expect(page).to have_link(link_text, wait: 5)
end

When('I click {string} on Ai Portfolio Report Page')  do |link_text|
  click_on link_text
end

Then('I should see the documents modal') do
  expect(page).to have_css('#documentsModal.show', wait: 10)
  expect(page).to have_content('Documents - Company Evaluation Agent')
end

Given('the portfolio company {string} has an evaluation folder with documents:') do |company_name, table|
  company = Investor.find_by!(name: company_name)

  ActiveRecord::Base.connected_to(role: :writing) do
    company.setup_document_folder unless company.document_folder
    company.reload

    eval_folder = company.document_folder.children.find_or_create_by(
      name: 'Company Evaluation Agent',
      entity_id: company.entity_id
    )

    table.hashes.each do |row|
      FactoryBot.create(:document,
        name: row['name'],
        folder: eval_folder,
        entity: company.entity,
        user: @user
      )
    end
  end
end

Given('the portfolio company {string} has an evaluation folder') do |company_name|
  company = Investor.find_by!(name: company_name)

  ActiveRecord::Base.connected_to(role: :writing) do
    company.setup_document_folder unless company.document_folder
    company.reload

    company.document_folder.children.find_or_create_by(
      name: 'Company Evaluation Agent',
      entity_id: company.entity_id
    )
  end
end

Then('I should see document {string} in the documents list') do |doc_name|
  within('#documentsModal') do
    expect(page).to have_content(doc_name, wait: 10)
  end
end

Then('I should see the documents table in the modal') do
  within('#documentsModal') do
    expect(page).to have_css('table', visible: true, wait: 10)
  end
end

Then('the documents table should have {int} row(s)') do |count|
  within('#documentsModal tbody') do
    expect(page).to have_css('tr', count: count, wait: 10)
  end
end

Then('I should see the upload documents section') do
  within('#documentsModal') do
    expect(page).to have_content('Upload New Documents')
    expect(page).to have_css('input[type="file"]', visible: :all)
  end
end

Then('I should see the {string} button') do |button_text|
  within('#documentsModal') do
    expect(page).to have_button(button_text, wait: 5)
  end
end

# Simulate what Uppy does after a file is uploaded to cache:
# It creates hidden input fields with the cached file JSON data.
When('I simulate uploading a file {string} in the modal') do |filename|
  cached_file_json = { id: "test_#{SecureRandom.hex(8)}", storage: "cache", metadata: { filename: filename, size: 1024, mime_type: "application/pdf" } }.to_json

  page.execute_script(<<~JS)
    const uploadArea = document.querySelector('[data-ai-portfolio-report-form-target="uploadArea"]');

    const fileInput = document.createElement('input');
    fileInput.type = 'hidden';
    fileInput.name = 'evaluation_docs[documents_attributes][0][file]';
    fileInput.value = '#{cached_file_json.gsub("'", "\\\\'")}';
    uploadArea.appendChild(fileInput);

    const nameInput = document.createElement('input');
    nameInput.type = 'hidden';
    nameInput.name = 'evaluation_docs[documents_attributes][0][name]';
    nameInput.value = '#{filename}';
    uploadArea.appendChild(nameInput);
  JS
end

When('I click the {string} button in the modal') do |button_text|
  within('#documentsModal') do
    click_button button_text
  end
end

Then('a document {string} should exist in the evaluation folder for {string}') do |doc_name, company_name|
  company = Investor.find_by!(name: company_name)
  eval_folder = company.document_folder.children.find_by(name: 'Company Evaluation Agent')
  expect(eval_folder).to be_present
  expect(eval_folder.documents.find_by(name: doc_name)).to be_present
end
