  Given('given there is a document {string} for the entity') do |arg|
    @document = FactoryBot.build(:document, entity: @entity, user: @entity.employees.sample)
    key_values(@document, arg)
    @document.save!
    puts "\n####Document####\n"
    puts @document.to_json
  end


  Given('I have {string} access to the document') do |should|
    Pundit.policy(@user, @document).show?.should == (should == "true")
  end

  Given('I should have {string} to the document') do |doc_access|
    Pundit.policy(@user, @document).show?.should == (doc_access == "true")
  end

  Given('I should not have access to the document') do
    Pundit.policy(@user, @document).show?.should == false
  end

  Then('another user has {string} access to the document') do |arg|
    Pundit.policy(@another_user, @document).show?.to_s.should == arg
  end

  Then('employee investor has {string} access to the document') do |arg|
    Pundit.policy(@employee_investor, @document).show?.to_s.should == arg
  end


Given('investor has access right {string} in the document') do |arg1|
    @access_right = AccessRight.new(owner: @document, entity: @entity)
    key_values(@access_right, arg1)
    puts @access_right.to_json
    
    @access_right.save!
    puts "\n####Access Right####\n"
    puts @access_right.to_json
end

Given('I am at the documents page') do
  visit(documents_path)
end

When('I create a new document {string} in folder {string}') do |args, folder_name|

  @folder = Folder.where("name like '%#{folder_name}%'").first

  @document = Document.new
  key_values(@document, args)
  @document.folder_id = @folder.id
  steps %(
    When I fill and submit the new document page
  )
end

When('I create a new document {string}') do |args|
  @folder = Folder.last || Folder.create!(name: "Test Folder", parent: Folder.first, folder_type: :regular, entity_id: Folder.first.entity_id)
  @document = Document.new
  key_values(@document, args)
  steps %(
    When I fill and submit the new document page
  )
end

When('I fill and submit the new document page') do
  find("#doc_actions").click
  click_on("New Document")
  #sleep(4)
  if page.has_css?("#document_name")
    fill_in("document_name", with: @document.name)
  elsif page.has_css?("#other_name")
    fill_in("other_name", with: @document.name)
  end

  fill_in("document_tag_list", with: @document.tag_list.join(",")) if @document.tag_list.present?
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(3)
  check('document_download') if @document.download
  check('document_printing') if @document.printing
  check('Send email', allow_label_click: true) if @document.send_email

  puts "Selecting #{@document.folder.name}" if @document.folder_id
  select(@document.folder.name, from: "document_folder_id") if @document.folder_id

  #sleep(3)
  click_on("Save")
  # sleep(5)
  expect(page).to have_text "Document was successfully saved."
end


Then('an document should be created') do
  @created_doc = Document.last
  puts "\n####Document####\n"
  puts @created_doc.to_json

  @created_doc.name.should == @document.name
  @created_doc.download.should == @document.download
  @created_doc.printing.should == @document.printing
  @created_doc.tag_list.should == @document.tag_list if @document.tag_list
  @created_doc.user_id.should == @user.id
  if @created_doc.owner != nil
    @created_doc.entity_id.should == @created_doc.owner.entity_id
  else
    @created_doc.entity_id.should == @user.entity_id
  end
  @document = @created_doc
end

Given('the entity has a folder {string}') do |args|
  @folder = Folder.new(parent: Folder.first, entity: @user.entity)
  key_values(@folder, args)
  @folder.save!
  puts @folder.to_json
end

Given('the entity has a child folder {string}') do |args|
  @child_folder = Folder.new(parent: @folder, entity: @user.entity)
  key_values(@child_folder, args)
  @child_folder.save!
  puts @child_folder.to_json
end


Given('the folder has access rights {string}') do |arg1|
  @access_right = AccessRight.new(owner: @folder, entity: @user.entity)
  key_values(@access_right, arg1)
  puts @access_right.to_json

  @access_right.save!
  puts "\n####Access Right####\n"
  puts @access_right.to_json
end

Then('the document should have the same access rights as the folder') do
  puts "\n####Document Access Right####\n"
  puts @document.reload.access_rights.to_json
  puts "\n####Folder Access Right####\n"
  puts @folder.reload.access_rights.to_json

  @document.access_rights.count.should == @folder.access_rights.count
  @document.access_rights.each_with_index do |dar, idx|
    far = @folder.access_rights[idx]
    far.access_to_investor_id.should == dar.access_to_investor_id
    far.access_to_category.should == dar.access_to_category
    far.entity_id.should == dar.entity_id
  end
end


Then('I should see the document details on the details page') do
  page.should have_content(@document.name)
  page.should have_content(@document.tag_list) if @document.tag_list
  # page.should have_content(@document.folder.full_path)
end

Then('I should see the document in all documents page') do
  visit(documents_path)
  page.should have_content(@document.name)
  page.should have_content(@document.tag_list) if @document.tag_list
  # page.should have_content(@document.folder.full_path)
end

Then('the deal document details must be setup right') do
  @deal.data_room_folder.name.should == "Overview"
  @deal.data_room_folder.owner.should == @deal

  @document.owner.should == @deal
  @document.folder.name.should == "Overview"
  @document.folder.full_path.should == "/Deals/#{@deal.name}/Overview"
end


Then('the sale document details must be setup right') do
  @document.owner.should == @sale
  @document.folder.name.should == @sale.name
  @document.folder.full_path.should == "/Secondary Sales/#{@sale.name}"
end

Then('the offer document details must be setup right') do
  @document.owner.should == @offer
  @document.folder.name.should == "#{@offer.user.full_name}-#{@offer.id}"
  @document.folder.full_path.should == "/Secondary Sales/#{@offer.secondary_sale.name}/Offers/#{@offer.user.full_name}-#{@offer.id}"
end

Then('the interest document details must be setup right') do
  @document.owner.should == @interest
  @document.folder.name.should == "#{@interest.interest_entity.name}-#{@interest.id}"
  @document.folder.full_path.should == "/Secondary Sales/#{@interest.secondary_sale.name}/Interests/#{@interest.interest_entity.name}-#{@interest.id}"
end



Given('I visit the deal investor details page') do
  @deal_investor = @deal.deal_investors.first
  visit( deal_investor_path(@deal_investor) )
end

When('the deal investor document details must be setup right') do
  @document.owner.should == @deal_investor
  @document.folder.name.should == "#{@deal_investor.investor_name}"
  @document.folder.full_path.should == "/Deals/#{@deal.name}/Deal Investors/#{@deal_investor.investor_name}"
end


Given('given there is a document {string} for the deal') do |args|
  @document = Document.new(entity: @deal.entity, name: "Test",
    text: Faker::Company.catch_phrase, user: @user, owner: @deal,
    folder: @deal.entity.folders.sample, file: File.new("public/sample_uploads/GrantLetter.docx", "r"))

  key_values(@document, args)
  @document.save!

  puts "\n####Document####\n"
  puts @document.to_json

end

Given('given there is a document {string} for the sale') do |args|
  @document = Document.new(entity: @sale.entity, name: "Test",
    text: Faker::Company.catch_phrase, user: @user, owner: @sale,
    folder: @sale.entity.folders.sample, file: File.new("public/sample_uploads/GrantLetter.docx", "r"))

  key_values(@document, args)
  @document.save!

  puts "\n####Document####\n"
  puts @document.to_json

end

Then('an email must go out to the investors for the document') do
  user = InvestorAccess.includes(:user).first.user
  subj = "#{@document.name} uploaded by #{@document.entity.name}"
  puts "Checking email for document #{@document.name} to #{user.email}"
  current_email = nil
  emails_sent_to(user.email).each do |email|
    puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
    current_email = email if email.subject == subj
  end
  expect(current_email.subject).to include subj
end

Given('the document is approved') do
  @document.approved = true
  @document.approved_by_id = @user.id
  @document.save
end

Given('user goes to add a new template {string} for the fund') do |doc_name|
  @es = @fund.entity.entity_setting
  @es.stamp_paper_tags = "GJ-100-BOB_Test,DL-100-test"
  @es.save!
  visit(fund_path(@fund))
  click_on("Actions")
  find('#misc_action_menu').hover
  click_on("New Template")
  #sleep(2)
  fill_in("document_name", with: doc_name)
  attach_file('files[]', File.absolute_path('./public/sample_uploads/SOA Template.docx'), make_visible: true)
  sleep(2)
  # check checkbox id id="document_template"
  check('document_template')
end

Then('user should be able to add esignatures') do
  click_on("Add Signature")
  expect(page).to have_text("Esign display on page")
  # click on form's text input field with id starting with document_e_signatures_attributes_...
  all("input[id^='document_e_signatures_attributes_']").first.click

  datalist = find('#label-list', visible:false)

  # Check for the presence of labels within the datalist
  datalist.all(:option, visible:false).each do |option|
    @fund.signature_labels.include?(option.value).should == true
  end
  all("input[id^='document_e_signatures_attributes_']").first.set(@fund.signature_labels.first)
end

Then('user should be able to add esignatures without label list') do
  click_on("Add Signature")
  expect(page).to have_text("Esign display on page")
  # click on form's text input field with id starting with document_e_signatures_attributes_...
  all("input[id^='document_e_signatures_attributes_']").first.click

  all("input[id^='document_e_signatures_attributes_']").first.set(@fund.signature_labels.first)
end

Then('user should be able to add estamp_stamps') do
  click_on("Add Stamp Paper")
  @fund.entity.entity_setting.stamp_paper_tags.split(",").each do |stamp_paper_tag|
    expect(page).to have_text stamp_paper_tag
  end
  expect(page).to have_text "Sign on page"
  expect(page).to have_text "Note on page"
  all("input[id^='document_stamp_papers_attributes_']").first.set("#{@fund.entity.entity_setting.stamp_paper_tags.split(",").first.strip}:1")
end

Then('user should be able to save the document') do
  click_on("Save")
  # sleep(2)
  expect(page).to have_text "Document was successfully saved."
end

Given('user goes to add a new document {string} for the fund') do |doc_name|
  @es = @fund.entity.entity_setting
  @es.stamp_paper_tags = "GJ-100-BOB_Test,DL-100-test"
  @es.save!
  visit(fund_path(@fund))
  # click on element with id documents_tab
  find("#documents_tab").click
  find("#doc_actions").click
  click_on("New Document")
  fill_in("document_name", with: doc_name)
  attach_file('files[]', File.absolute_path('./public/sample_uploads/SOA Template.docx'), make_visible: true)
  sleep(2)
  # check checkbox id id="document_template"
  check('document_template')
end

Then('the template checkbox is not present') do
  expect(page).not_to have_text "Template"
  expect(page).not_to have_selector('#document_template')
end

Given('there is a Custom Notification for the entity') do
  @document = Document.first
  allow_any_instance_of(Document).to receive(:notification_users).and_return([@user])
  @custom_notification = FactoryBot.create(:custom_notification, entity: @entity, owner: @entity, for_type: "Send Document", body: Faker::Lorem.paragraphs.join(". "), email_method: "send_document")
end

Then('user sends a single document using that Custom Notification') do
  visit document_path(@document)
  click_on "Send Document"
  click_on "Send #{@custom_notification.subject}"
  expect(page).to have_text "Document will be sent to the email addresses as requested."
end

Then('user recieves the document in email with a custom notification template') do
  expect(@custom_notification.subject).to(eq(open_email(@user.email).subject))
  expect(current_email.body).to(include(@custom_notification.body))
  expect(current_email.attachments.first.filename).to(include(@document.name))
end

Given('the template has permissions {string}') do |permissions|
  #sleep(2)
  @template = Document.last
  key_values(@template, permissions)
  @template.save
end

Then('the generated SOA has permissions {string}') do |permissions|
  @document = Document.where(owner_tag: "Generated").last
  key_val = permissions.split(";").to_h { |kv| kv.split("=") }
  key_val.each do |k, v|
    puts "Asserting #{k} to #{v} on #{@document.name}"
    @document.send("#{k}").to_s.should == v
  end
end

Given('investor has access right {string} in the folder') do |arg1|
  @access_right = AccessRight.new(owner: @folder, entity: @entity)
  key_values(@access_right, arg1)
  puts @access_right.to_json

  @access_right.save
  puts "\n####Access Right####\n"
  puts @access_right.to_json
end

Given('given there is a Folder {string} for the entity') do |args|
  @entity ||= Entity.first
  @folder = Folder.new(entity: @entity, name: "Test Folder")
  key_values(@folder, args)
  @folder.save!
  puts "\n####Folder####\n"
  puts @folder.to_json
end

Given('the folder has a subfolder {string}') do |args|
  @entity ||= Entity.first
  @subfolder = Folder.new(entity: @entity, name: "Sub Folder", parent: @folder)
  key_values(@subfolder, args)
  @subfolder.save!
  puts "\n####Sub Folder####\n"
  puts @subfolder.to_json
end

Given('given there is a document {string} under the folder') do |string|
  @document = Document.new(entity: @entity, name: "Test",
    folder: @subfolder, file: File.new("public/sample_uploads/GrantLetter.docx", "r"), user_id: 1)
  key_values(@document, string)
  @document.save!

  puts "\n####Document####\n"
  puts @document.to_json
end

Given('I create a new Stakeholder {string} and save') do |args|
  @temp_inv = FactoryBot.build(:investor)
  key_values(@temp_inv, args)
  visit(investors_path)
  click_on("New")
  fill_in('investor_investor_name', with: @temp_inv.investor_name)
  select(@temp_inv.category, from: "investor_category")
  fill_in('investor_primary_email', with: @temp_inv.primary_email)
  click_on("Save")
  sleep(1)
  @investor = Investor.last
end

When('I go to see the investor documents of the entity') do
  visit("/documents/investor?entity_id=#{@entity.id}")
  sleep(3)
end

Then('I cannot see the documents') do
  expect(page).not_to have_text(@folder.name)
  expect(page).not_to have_text(@subfolder.name)
  expect(page).not_to have_text(@document.name)
end

When('I go to see the document') do
  visit(document_path(@document))
end

Then('I should see the documents') do
  expect(page).to have_text(@folder.name)
  expect(page).to have_text(@document.name)
end

Then('I should see the documents details') do
  expect(page).to have_text("Viewing: #{@document.name}")
end

Given('folders access right is deleted') do
  AccessRight.where(owner: @folder).destroy_all
end
