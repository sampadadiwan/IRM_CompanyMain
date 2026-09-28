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
  (!!@created_doc.download).should == (!!@document.download)
  (!!@created_doc.printing).should == (!!@document.printing)
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
  attach_file('files[]', File.absolute_path('./public/sample_uploads/Investor Statement Template.docx'), make_visible: true)
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
  attach_file('files[]', File.absolute_path('./public/sample_uploads/Investor Statement Template.docx'), make_visible: true)
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
  stub_document_notification_recipients(@user)
  @custom_notification = FactoryBot.create(:custom_notification, entity: @entity, owner: @entity, for_type: "Send Document", body: Faker::Lorem.paragraphs.join(". "), email_method: "send_document")
end

Given('there is a Custom Notification with placeholders for the entity') do
  @document = Document.first
  stub_document_notification_recipients(@user)
  @custom_notification = CustomNotification.create!(
    entity: @entity,
    owner: @entity,
    for_type: "Send Document",
    email_method: "send_document",
    subject: "Document with Placeholders",
    body: "Dear {{user_full_name}}, document {{document_name}} is ready. Unknown: {{not_a_real_placeholder}}.",
    enabled: true
  )
end

Then('the document notification placeholders are resolved correctly') do
  open_email(@user.email)
  expect(current_email).not_to be_nil
  body = current_email.body.to_s

  # Known DocumentMailer placeholders resolved
  expect(body).not_to include("{{user_full_name}}")
  expect(body).not_to include("{{document_name}}")
  expect(body).to include(@document.name)

  # Unknown placeholder preserved
  expect(body).to include("{{not_a_real_placeholder}}")
end

Given('there is a Custom Notification with commitment placeholders for the entity') do
  @custom_notification = CustomNotification.create!(
    entity: @entity,
    owner: @entity,
    for_type: "Send Document",
    email_method: "send_document",
    subject: "Commitment Document with Placeholders",
    body: "Dear {{kyc_full_name}}, folio {{folio_id}}, amount {{committed_amount}} for {{document_name}}. Unknown: {{not_a_real_placeholder}}.",
    enabled: true
  )
end

When('the commitment document is sent using that Custom Notification') do
  DocumentSender.send(@document, @user.id, @custom_notification.id)
end

Then('the document notification commitment placeholders are resolved correctly') do
  recipient = @capital_commitment.investor.notification_users.first
  open_email(recipient.email)
  expect(current_email).not_to be_nil
  body = current_email.body.to_s

  # kyc_full_name/folio_id/committed_amount fall back to document.capital_commitment since
  # this document's owner is the CapitalCommitment, not an InvestorKyc directly.
  expect(body).to include(@capital_commitment.investor_kyc.full_name)
  expect(body).not_to include("{{kyc_full_name}}")

  expect(body).to include(@capital_commitment.folio_id)
  expect(body).not_to include("{{folio_id}}")

  expect(body).to include(@capital_commitment.committed_amount.format)
  expect(body).not_to include("{{committed_amount}}")

  expect(body).to include(@document.name)
  expect(body).not_to include("{{document_name}}")

  # Unknown placeholder preserved
  expect(body).to include("{{not_a_real_placeholder}}")
end

# Proves DocumentNotifier#email_data forwards the owning CapitalCommitment's cc via
# additional_ccs when a document filed under a commitment is sent via "Send Document".
Then('the commitment document notification email is cc\'d to {string}') do |cc_email|
  recipient = @capital_commitment.investor.notification_users.first
  open_email(recipient.email)
  expect(current_email).not_to be_nil, "No email delivered to #{recipient.email}"
  expect(current_email.cc).to include(cc_email),
                              "Expected cc #{cc_email} on email to #{recipient.email}, got #{current_email.cc.inspect}"
end

Then('user sends a single document using that Custom Notification') do
  visit document_path(@document)
  click_on "Send Document"
  click_on "Send #{@custom_notification.subject}"
  click_on "Proceed"
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

Then('the generated Investor Statement has permissions {string}') do |permissions|
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

Given('the template {string} has attrs {string}') do |template_name, template_attrs|
  @template ||= Document.templates.where(name: template_name).last
  key_values(@template, template_attrs)
  @template.save!
end

Given('the KYC associated with the commitment has the document {string} with file {string}') do |document_name, file_name|
  @capital_commitment = CapitalCommitment.last

  @investor_kyc = InvestorKyc.last
  Document.create!(entity: @investor_kyc.entity, name: document_name, owner: @investor_kyc, folder: @investor_kyc.document_folder,
  user: @user, file: File.new("public/sample_uploads/merge_test/#{file_name}", "r"))
  expect(@investor_kyc.documents.where(name: document_name).count).to eq(1)
end

Given('the commitment has document {string} with file {string}') do |document_name, file_name|
  Document.create!(entity: @capital_commitment.entity, name: document_name, owner: @capital_commitment, folder: @capital_commitment.document_folder,
  user: @user, file: File.new("public/sample_uploads/merge_test/#{file_name}", "r"))
end

Given('there is a document {string} owned by the commitment with file {string}') do |document_name, file_name|
  @document = Document.create!(entity: @capital_commitment.entity, name: document_name, owner: @capital_commitment, folder: @capital_commitment.document_folder,
  user: @user, file: File.new("public/sample_uploads/merge_test/#{file_name}", "r"))
end

When('I create a new document {string} with no file') do |args|
  @folder = Folder.last || Folder.create!(name: "Test Folder", parent: Folder.first, folder_type: :regular, entity_id: Folder.first.entity_id)
  @temp_document = Document.new
  key_values(@temp_document, args)

  find("#doc_actions").click
  click_on("New Document")
  if page.has_css?("#document_name")
    fill_in("document_name", with: @temp_document.name)
  elsif page.has_css?("#other_name")
    fill_in("other_name", with: @temp_document.name)
  end

  fill_in("document_tag_list", with: @temp_document.tag_list.join(",")) if @temp_document.tag_list.present?
  # attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(3)
  check('document_download') if @temp_document.download
  check('document_printing') if @temp_document.printing
  check('Send email', allow_label_click: true) if @temp_document.send_email

  puts "Selecting #{@temp_document.folder.name}" if @temp_document.folder_id
  select(@temp_document.folder.name, from: "document_folder_id") if @temp_document.folder_id

  click_on("Save")
end

Then('I should see the document file validation error on creation') do
  # check below error in a popup
  expect(page).to have_text("Please correct the errors on the form before proceeding.")
end

Then('I should see the document file validation error on update') do
  expect(page).to have_text("File can't be blank")
end

Given('I upload a valid file for the document') do
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
end

Given('I go to edit the document') do
  @document ||= Document.order(:created_at).last
  visit edit_document_path(@document)
end

Given('I fill the document form') do
  fill_in("document_name", with: @document.name)
  fill_in("document_tag_list", with: @document.tag_list.join(",")) if @document.tag_list.present?
  check('document_download') if @document.download
  check('document_printing') if @document.printing
  check('Send email', allow_label_click: true) if @document.send_email
  select(@document.folder.name, from: "document_folder_id") if @document.folder_id
end

Given('I remove the file from the document') do
  @document.file = nil
  @document.save(validate: false)
end

Then('the document should contain the text {string}') do |content|
  if @reader.nil?
    @generated_document = Document.generated.last
    file = @generated_document.file.download
    @reader = PDF::Reader.new(file.path)
    @pdf_text = @reader.pages.map(&:text).join(" ")
  end
  # Concatenate all pages to search for the text string
  puts "Checking for text '#{content}'"
  expect(@pdf_text).to include(content), "Expected PDF to contain '#{content}' but it was missing."
end

Then('the document should contain an image with dimensions {int}x{int}') do |width, height|
  if @reader.nil?
    @generated_document = Document.generated.last
    file = @generated_document.file.download
    @reader = PDF::Reader.new(file.path)
  end

  found_dimensions = []
  found_match = false

  @reader.pages.each do |page|
    next unless page.xobjects

    page.xobjects.each do |_name, stream|
      next unless stream.hash[:Subtype] == :Image

      w = stream.hash[:Width]
      h = stream.hash[:Height]
      found_dimensions << "#{w}x#{h}"
      puts "Found image with dimensions #{w}x#{h}"
      # Check for exact match
      if w == width && h == height
        found_match = true
        break
      end
    end
    break if found_match
  end

  expect(found_match).to be(true), "Expected image #{width}x#{height} not found. Found images with dimensions: #{found_dimensions.join(', ')}"
end

# -----------------------------------------------------------------------
# as_of date steps
# -----------------------------------------------------------------------

When('I create a new document {string} with as_of {string}') do |args, as_of_date|
  @folder = Folder.last || Folder.create!(name: "Test Folder", parent: Folder.first, folder_type: :regular, entity_id: Folder.first.entity_id)
  @document = Document.new
  key_values(@document, args)
  @as_of_date = Date.parse(as_of_date)

  find("#doc_actions").click
  click_on("New Document")
  if page.has_css?("#document_name")
    fill_in("document_name", with: @document.name)
  elsif page.has_css?("#other_name")
    fill_in("other_name", with: @document.name)
  end
  fill_in("document_as_of", with: as_of_date)
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(3)
  check('document_download') if @document.download
  check('document_printing') if @document.printing
  click_on("Save")
  expect(page).to have_text "Document was successfully saved."
  @document = Document.last
end

Then('the document should have as_of date {string}') do |as_of_date|
  @document = Document.order(:created_at).last
  expect(@document.as_of).to eq(Date.parse(as_of_date))
end

Then('the document grid should show the as_of date for the document') do
  visit(documents_path)
  expected = I18n.l(@document.as_of)
  expect(page).to have_content(expected)
end

Then('the generated investor statement has as_of equal to end date') do
  doc = @capital_commitment.documents.generated.last
  puts "Checking as_of: doc.as_of=#{doc.as_of}, end_date=#{@end_date.to_date}"
  expect(doc.as_of).to eq(@end_date.to_date)
end

# ─────────────────────────────────────────────────────────────────────────────────────────────
# Fund data room notifications. A data room document is owned by the Fund (Folder owner, see
# WithDataRoom), so it has no commitment of its own to read a cc from and no single investor -
# the delivering access right supplies both. See
# docs/modules/notifications/document_notification_cc_resolution.md.
# ─────────────────────────────────────────────────────────────────────────────────────────────

Given('the investor contact has cc {string}') do |cc|
  @investor_access.update!(cc:)
  expect(@investor_access.reload.cc).to include(cc.split(",").first)
end

When('a document {string} is uploaded to the fund data room') do |document_name|
  @fund.reload
  # send_email: true is what triggers Document#send_notification_for_owner via
  # DocumentPostCreateJob. ActiveJob runs inline in test, so the emails are delivered here.
  @document = Document.create!(entity: @fund.entity, name: document_name,
                               folder: @fund.data_room_folder, send_email: true, user: @user,
                               file: File.new("public/sample_uploads/merge_test/CapHive - GST Certificate.pdf", "r"))
  # setup_folder derives owner from the folder, which is what makes this a Fund-owned document.
  expect(@document.owner_type).to eq("Fund")
end

Then('the data room document notification email is cc\'d to {string}') do |cc_email|
  open_email(@investor_user.email)
  expect(current_email).not_to be_nil, "No email delivered to #{@investor_user.email}"
  expect(current_email.cc).to include(cc_email),
                              "Expected cc #{cc_email} on the data room email to #{@investor_user.email}, got #{current_email.cc.inspect}"
end

Then('the data room document notifies the same people the access rights resolve to') do
  # The old resolution, replicated: every access right's users, flattened and uniq'd. The new
  # per-access-right fan-out must email exactly this set of people - no more, no fewer.
  expected = (@document.access_rights.map(&:users).flatten +
              @document.owner.access_rights.map(&:users).flatten).compact.map(&:id).uniq.sort

  expect(@document.notification_users.map(&:id).uniq.sort).to eq(expected)
end

Then('each data room notification recipient carries the stakeholder its access right names') do
  pairs = @document.notification_recipients
  expect(pairs).not_to be_empty

  pairs.each do |user, investor|
    expect(investor).not_to be_nil, "No stakeholder resolved for #{user.email} - its cc addresses would be lost"
    expect(investor.id).to eq(@investor.id)
  end
end

Then('duplicate access rights for one stakeholder produce a single notification') do
  # The stakeholder is reachable twice: through the document's OWN access right (copied from the
  # data room folder by setup_access_rights) and through the FUND's, which notification_recipients
  # unions in. Those are separate rows with different owners, so AccessRight#access_is_unique does
  # not collapse them - it only forbids two rows with the same owner. The dedupe on
  # [user_id, investor_id] is what turns them into one email.
  doc_rights = @document.access_rights.where(access_to_investor_id: @investor.id).count
  fund_rights = @document.owner.access_rights.where(access_to_investor_id: @investor.id).count
  expect(doc_rights + fund_rights).to be > 1,
                                      "Expected the stakeholder to be reachable through more than one access right " \
                                      "(document: #{doc_rights}, fund: #{fund_rights}) to exercise the dedupe"

  for_investor = @document.notification_recipients.select { |_user, investor| investor&.id == @investor.id }
  expect(for_investor.map { |user, _investor| user.id }.uniq.size).to eq(for_investor.size)
end

Given('every access right for the stakeholder is revoked') do
  AccessRight.where(access_to_investor_id: @investor.id).find_each(&:destroy)
  expect(AccessRight.where(access_to_investor_id: @investor.id).count).to eq(0)
end

Then('uploading a document to the fund data room logs the stakeholder as committed but without access') do
  expect(Rails.logger).to receive(:warn)
    .with(/hold a commitment in this fund but no access right delivers this document/)
    .at_least(:once)

  steps %(
    When a document "Fund Update Q4" is uploaded to the fund data room
  )
end

Given("one stakeholder contact's login row has been deleted") do
  accesses = @investor.approved_investor_accesses.order(:id).to_a
  expect(accesses.size).to be > 1, "Need at least two contacts so one can be orphaned"
  @orphaned_access = accesses.first
  @surviving_access = accesses.last

  # delete_all, not destroy: User has `has_many :investor_accesses, dependent: :destroy`, so a
  # destroy would take the contact row with it and there would be nothing orphaned. A hard delete
  # leaves investor_accesses.user_id pointing at a row that no longer exists - exactly the state
  # found on the production dump.
  User.where(id: @orphaned_access.user_id).delete_all
  expect(User.exists?(@orphaned_access.user_id)).to be(false)
end

Then('the remaining stakeholder contact still receives the data room notification') do
  open_email(@surviving_access.email)
  expect(current_email).not_to be_nil,
                              "The orphaned contact blocked the whole notification - nobody received #{@document.name}"

  resolved = @document.notification_recipients.map { |user, _investor| user.email }
  expect(resolved).to include(@surviving_access.email)
  expect(resolved).not_to include(@orphaned_access.email)
end

Then('the data room document notification email cc\'s {string} exactly once') do |cc_email|
  open_email(@investor_user.email)
  expect(current_email).not_to be_nil, "No email delivered to #{@investor_user.email}"
  occurrences = current_email.cc.to_a.count { |addr| addr.to_s.casecmp?(cc_email) }
  expect(occurrences).to eq(1),
                         "Expected #{cc_email} exactly once, found it #{occurrences} time(s) in #{current_email.cc.inspect}"
end
