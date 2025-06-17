Given('a document named {string} exists for {string}') do |document_name, entity_name|
  entity = Entity.find_by(name: entity_name)
  @document = FactoryBot.create(:document, name: document_name, entity: entity, user: @user, text: "This is a test document for #{entity_name}.")
end

Given('a doc share exists for {string} with email {string} and email sent is true') do |document_name, email|
  document = Document.find_by(name: document_name)
  @doc_share = FactoryBot.build(:doc_share, document: document, email: email, email_sent: true)
  DocShareCreationService.wtf?(doc_share: @doc_share).success?.should == true
end

Given('a doc share exists with email {string} and email sent is true') do |email|
  @doc_share = FactoryBot.build(:doc_share, email: email, email_sent: true, document: @document) 
  DocShareCreationService.wtf?(doc_share: @doc_share).success?.should == true
end

Given('a doc share exists for {string} with email {string} and email sent is false') do |document_name, email|
  document = Document.find_by(name: document_name)
  @doc_share = FactoryBot.build(:doc_share, document: document, email: email, email_sent: false)
  DocShareCreationService.wtf?(doc_share: @doc_share).success?.should == true
end

Given('a doc share exists for {string} with email {string}') do |document_name, email|
  document = Document.find_by(name: document_name)
  @doc_share = FactoryBot.build(:doc_share, document: document, email: email)
  DocShareCreationService.wtf?(doc_share: @doc_share).success?.should == true
end

Given('the doc share has a token {string}') do |token_type|
  service = DocShareTokenService.new
  case token_type
  when "valid_token"
    @doc_share_token_string = service.generate_token(@doc_share.id)
  when "invalid_token"
    @doc_share_token_string = "thisisnotavalidtoken" # A string that will fail verification
  when "non_existent_doc_share_token"
    @doc_share_token_string = service.generate_token(99999) # A non-existent ID
  else
    @doc_share_token_string = service.generate_token(@doc_share.id)
  end
end

Given('the doc share is not associated with any document') do
  @doc_share.update_column(:document_id, nil)
end

When('I visit the view link for the doc share with token {string}') do |token_placeholder|
  if token_placeholder == "invalid_token"
    @doc_share_token_string = "thisisnotavalidtoken" # A string that will fail verification
  end
  visit view_doc_shares_path(token: @doc_share_token_string)
end

Then('I should be able to view the document {string}') do |string|
  expect(page).to have_content(string)
  expect(page).to have_content(@document.name)
  expect(page).to have_content(@document.text.to_plain_text)
  sleep(10)
end


Then('I should be redirected to the document show page for {string}') do |document_name|
  document = Document.find_by(name: document_name)
  expect(current_path).to eq(document_path(document))
end

Then('the doc share\'s view count should be {int}') do |count|
  expect(@doc_share.reload.view_count).to eq(count)
end

Then('the doc share\'s viewed at should be present') do
  expect(@doc_share.reload.viewed_at).to be_present
end

Then('I should see a {string} page with status {int}') do |page_content, status_code|
  expect(page.status_code).to eq(status_code)
  expect(page).to have_content(page_content)
end

Then('the doc share email address receives an email with {string} in the subject') do |subject|
  open_email(@doc_share.email)
  expect(current_email.subject).to include subject
end