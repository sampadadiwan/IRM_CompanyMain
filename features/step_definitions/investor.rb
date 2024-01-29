require 'cucumber/rspec/doubles'
require 'net/http'
require 'uri'

Given('I am at the investor page') do
  visit("/investors")
end

When('I create a new investor {string}') do |arg1|
  @investor_entity = FactoryBot.build(:entity, entity_type: "Investor")
  key_values(@investor_entity, arg1)
  click_on("New Stakeholder")

  if (Entity.vcs.count > 0)
    fill_in('investor_investor_name', with: @investor_entity.name)
    find('ui-menu-item-wrapper', text: @investor_entity.name).click if page.has_css?(".ui-menu-item-wrapper")
  end
  fill_in('investor_investor_name', with: @investor_entity.name)
  fill_in('investor_pan', with: @investor_entity.pan)
  fill_in('investor_primary_email', with: @investor_entity.primary_email)
  select("Founder", from: "investor_category")

  click_on("Save")
end

When('I update the investor {string}') do |args|
  @investor = Investor.last
  key_values(@investor, args)
  @investor.investor_name += " Updated"
  visit(edit_investor_path(@investor))

  fill_in('investor_investor_name', with: @investor.investor_name)
  fill_in('investor_pan', with: @investor.pan)
  select("Founder", from: "investor_category")
  fill_in('investor_tag_list', with: @investor.tag_list)
  fill_in('investor_primary_email', with: @investor_entity.primary_email)

  click_on("Save")

end

Then('an investor should be created') do
  @investor = Investor.last
  @investor.investor_name.include?(@investor_entity.name).should == true
  @investor.category.should == "Founder"
end

Then('an investor entity should be created') do
  puts @investor.to_json
  @investor_entity = Entity.find_by(name: @investor.investor_name)
  @investor.investor_name.include?(@investor_entity.name).should == true
  @investor.investor_entity_id.should == @investor_entity.id
  @investor.entity_id.should == @user.entity_id
  @investor.primary_email.should == @investor_entity.primary_email
end

Then('an investor entity should not be created') do
  Entity.where(name: @investor.investor_name).count.should == 1

  @investor_entity.name.include?(@investor_entity.name).should == true
  @investor.investor_entity_id.should == @investor_entity.id
  @investor.entity_id.should == @user.entity_id
end

Then('I should see the investor details on the details page') do
  visit investor_path(@investor)
  find(".show_details_link").click
  expect(page).to have_content(@investor.investor_name)
  expect(page).to have_content(@investor.category)
  expect(page).to have_content(@investor.primary_email)
  expect(page).to have_content(@investor.entity.name)
  expect(page).to have_content(@investor.tag_list) if @investor.tag_list.present?
end

Given('there is an existing investor entity {string} with employee {string}') do |arg1, arg2|

  steps %(
      Given there is an existing investor "#{arg1}"
    )

  @employee_investor = FactoryBot.create(:user, entity: @investor_entity)
  key_values(@employee_investor, arg2)
  @employee_investor.save
  puts "\n####Employee Investor####\n"
  puts @employee_investor.to_json
  @holdings_investor = @employee_investor

  @investor_entity.reload
end


Given('there is an existing investor {string}') do |arg1|
  steps %(
        Given there is an existing investor entity "#{arg1}"
    )
  @investor = FactoryBot.create(:investor, investor_entity_id: @investor_entity.id, entity_id: @entity.id)

  puts "\n####Investor####\n"
  puts @investor.to_json
end

Given('there is an existing portfolio company {string}') do |arg1|
  steps %(
        Given there is an existing investor entity "#{arg1}"
    )
  @investor = FactoryBot.create(:investor, investor_entity_id: @investor_entity.id, entity_id: @entity.id, category: "Portfolio Company")

  puts "\n####Portfolio Company####\n"
  puts @investor.to_json
end


Given('there is an existing investor {string} with {string} users') do |arg1, count|
  steps %(
        Given there is an existing investor entity "#{arg1}"
    )
  @investor = FactoryBot.create(:investor, investor_entity_id: @investor_entity.id, entity_id: @entity.id)
  (1..count.to_i).each do
    @investor_user = FactoryBot.create(:user, entity: @investor_entity)
    @investor_access = InvestorAccess.create!(investor: @investor, user: @investor_user,
                                            entity_id: @investor.entity_id,
                                            first_name: @investor_user.first_name,
                                            last_name: @investor_user.last_name,
                                            email: @investor_user.email, approved: true)

    puts "\n####Investor User####\n"
    puts @investor_user.to_json
    puts "\n####Investor Access####\n"
    puts @investor_access.to_json
  end

  puts "\n####Investor####\n"
  puts @investor.to_json
end

Given('there are {string} existing investor {string}') do |count, arg1|
  (1..count.to_i).each do
    steps %(
      Given there is an existing investor "#{arg1}"
    )
  end
end


Given('there is an existing investor entity {string}') do |arg1|
  @investor_entity = FactoryBot.build(:entity, entity_type: "Investor")
  key_values(@investor_entity, arg1)
  @investor_entity.save!
  puts "\n####Investor Entity####\n"
  puts @investor_entity.to_json
  EntityIndex.import
end

When('I create a new investor {string} for the existing investor entity') do |args|
  @new_investor = FactoryBot.build(:investor)
  key_values(@new_investor, args)
  click_on("New Stakeholder")

  fill_in('investor_investor_name', with: @investor_entity.name)
  first('.ui-menu-item-wrapper', text: @investor_entity.name).click if page.has_css?(".ui-menu-item-wrapper")
  fill_in('investor_pan', with: @new_investor.pan)
  fill_in('investor_primary_email', with: @new_investor.primary_email)
  select("Founder", from: "investor_category")

  click_on("Save")
end


Given('Given I upload an investor access file for employees') do
  # Sidekiq.redis(&:flushdb)

  visit(investor_path(Investor.first))
  find("#stakeholder_users_tab").click
  find("#upload_stakeholder_users").click

  fill_in('import_upload_name', with: "Test Investor Access Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(1)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('the investor accesses must have the data in the sheet') do
  file = File.open('./public/sample_uploads/investor_access.xlsx', "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportPreProcess.new.get_headers(data.row(1)) # get header row

  investor_accesses = @entity.investor_accesses
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    ia = investor_accesses[idx-1]
    puts "Checking import of #{ia.investor.investor_name}"
    ia.investor.investor_name.should == user_data["Investor"].strip
    ia.email.should == user_data["Email"]
    ia.cc.should == user_data["Cc"]
    ia.first_name.should == user_data["First Name"]
    ia.last_name.should == user_data["Last Name"]
    ia.phone.should == user_data["Phone"]&.to_s
    ia.approved.should == (user_data["Approved"] == "Yes" ? true : false)
    ia.whatsapp_enabled.should == (user_data["WhatsApp Enabled"] == "Yes" ? true : false)
    ia.import_upload_id.should == ImportUpload.last.id
  end

end


Given('Given I upload an investor kyc file for employees') do
  # Sidekiq.redis(&:flushdb)

  visit(investor_kycs_path)
  click_on("Upload/Download")
  click_on("Upload KYC Details")
  fill_in('import_upload_name', with: "Test Investor Access Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_kycs.xlsx'), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(1)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end


Then('There should be {string} investor access created') do |count|
  InvestorAccess.count.should == count.to_i
end


Given('Given I upload an investors file for the company') do
  visit(investors_path)
  click_on("Actions")
  click_on("Upload")
  sleep(3)
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investors.xlsx'), make_visible: true)
  sleep(4)
  click_on("Save")
  sleep(5)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
end

Given('the investors have approved investor access') do
  @entity.investors.each do |investor|
    ia = FactoryBot.create(:investor_access, investor: investor, entity: investor.entity, approved: true)
  end
end

Then('There should be {string} investors created') do |count|
  @entity.investors.not_holding.not_trust.count.should == count.to_i
end

Then('the investors must have the data in the sheet') do
  file = File.open('./public/sample_uploads/investors.xlsx', "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportPreProcess.new.get_headers(data.row(1)) # get header row

  investors = @entity.investors.not_holding.not_trust.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    inv = investors[idx-1]
    puts "Checking import of #{inv.investor_name}"
    inv.investor_name.should == user_data["Name"].strip
    inv.tag_list.should == user_data["Tags"]
    inv.category.should == user_data["Category"]
    inv.city.should == user_data["City"]
    inv.primary_email.should == user_data["Primary Email"]
    inv.import_upload_id.should == ImportUpload.last.id
  end

end


Given('Given I upload an investors file for the fund') do
  visit(investors_path)
  click_on("Actions")
  click_on("Upload")
  sleep(1)
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/fund_investors.xlsx'), make_visible: true)
  sleep(4)
  click_on("Save")
  sleep(4)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('the investors must be added to the fund') do
  @fund.reload
  # puts @fund.investors.to_json
  investors = @entity.investors.not_holding.not_trust.to_set
  fund_investors = @fund.investors.to_set
  investors.length.should == fund_investors.length

  investors.should == fund_investors

end

Then('There should be {string} investor kycs created') do |count|
  @entity.investor_kycs.count.should == count.to_i
end

Then('the investor kycs must have the data in the sheet') do
  file = File.open("./public/sample_uploads/investor_kycs.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportPreProcess.new.get_headers(data.row(1)) # get header row

  investor_kycs = @entity.investor_kycs.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = investor_kycs[idx-1]
    ap cc

    puts "Checking import of #{cc.full_name} #{cc.class.name}}"
    if user_data["Full Name"].present?
      cc.full_name.should == user_data["Full Name"]
      cc.birth_date.to_date.should == user_data["Date Of Birth"]
      cc.address.should == user_data["Address"]
      cc.corr_address.should == user_data["Correspondence Address"]
      cc.PAN.should == user_data["Pan"]
      cc.bank_name.should == user_data["Bank Name"]
      cc.bank_branch.should == user_data["Branch Name"]
      cc.bank_account_number.should == user_data["Bank Account Number"]&.to_s
      cc.ifsc_code.should == user_data["Ifsc Code"]&.to_s
      cc.esign_emails.should == user_data["Investor Signatory Emails"]
      cc.import_upload_id.should == ImportUpload.last.id
    end
    cc.class.name.should == cc.type_from_kyc_type
  end
end



Then('the approved investor access should receive a notification') do
  InvestorKyc.all.each do |kyc|
    kyc.investor.approved_users.each do |user|
      open_email(user.email)
      expect(current_email.subject).to eq "Request to add KYC: #{kyc.entity.name}"
    end
  end
end

Then('Aml Report should be generated for each investor kyc') do
  investor_kycs = @entity.investor_kycs
  investor_kycs.each do |kyc|
    if kyc.full_name.present?
      kyc.aml_reports.count.should_not == 0
      kyc.aml_reports.each do |report|
        report.name.should == kyc.full_name
      end
    end
  end
end

Given('Given Entity has ckyc_enabled kra_enabled set to true') do
  @entity.update(enable_kycs: true)
  @user.permissions.set(:enable_kycs)
  @user.save!
  @user.reload
  @entity.entity_setting.update(kra_enabled: true, ckyc_enabled: true, fi_code: "123456", aml_enabled: true)
  @investor = FactoryBot.create(:investor, entity: @entity, investor_entity: Entity.first)
end

Given('I create a new InvestorKyc with pan {string}') do |string|
  visit(investor_kycs_path)
  sleep(2)
  click_on("New KYC")
  click_on("Individual")
  sleep(2)
  class_name = "individual_kyc" #@investor_kyc.type_from_kyc_type.underscore
  fill_in("#{class_name}_birth_date", with: Date.today - 20.years)
  fill_in("#{class_name}_PAN", with: "PANNUMBER1")
  click_on("Next")
  sleep(3)
end

Given('I create a new InvestorKyc') do
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity)
  # @investor_kyc.save(validate: false)
  puts "\n########### KYC ############"
  puts @investor_kyc.to_json

  class_name = @investor_kyc.type_from_kyc_type.underscore


  visit(investor_kycs_path)
  click_on("New KYC")
  click_on("Individual")

  sleep(5)
  select(@investor_kyc.investor.investor_name, from: "#{class_name}_investor_id")
  fill_in("#{class_name}_full_name", with: @investor_kyc.full_name)
  select(@investor_kyc.residency.titleize, from: "#{class_name}_residency")
  fill_in("#{class_name}_PAN", with: @investor_kyc.PAN)
  fill_in("#{class_name}_birth_date", with: @investor_kyc.birth_date)

  click_on("Next")
  sleep(1)
  fill_in("#{class_name}_address", with: @investor_kyc.address)
  fill_in("#{class_name}_corr_address", with: @investor_kyc.corr_address)
  fill_in("#{class_name}_bank_account_number", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_ifsc_code", with: @investor_kyc.ifsc_code)
  click_on("Next")
  sleep(1)

  fill_in("#{class_name}_expiry_date", with: @investor_kyc.expiry_date)
  fill_in("#{class_name}_comments", with: @investor_kyc.comments)
  click_on("Save")
  sleep(1)

end

Then('I should see ckyc and kra data comparison page') do
  expect(page).to have_content("CKYC")
  expect(page).to have_content("KRA")

end

Then('I can send KYC reminder to approved users') do
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @investor.entity, investor: @investor, verified: false)
  @investor_kyc.save(validate: false)
  entity = @investor_kyc.entity
  investor = @investor_kyc.investor
  @users = FactoryBot.create_list(:user, 2, entity: @investor.investor_entity)
  @users.each do |user|
    InvestorAccess.create!(investor: investor, user: user,
    entity_id: investor.entity_id,
    first_name: user.first_name,
    last_name: user.last_name,
    email: user.email, approved: true)
  end
  @last_user = @users.last
  @last_user.update(whatsapp_enabled: true,phone: "1234567890", call_code: "91")
  @last_user.entity.entity_setting.update(sandbox_numbers: "917721046692", sandbox: true)
  investor.entity.permissions.set(:enable_whatsapp)
  investor.entity.save!
  visit(investor_kycs_path)
  sleep(2)
  click_on("Send KYC Reminders")
  sleep(1)
  click_on("Proceed")
  sleep(2)
  expect(page).to have_content("KYC Reminder sent successfully")
end

Then('Notifications are created for KYC Reminders') do
  Notification.where(recipient_id: @users.pluck(:id)).count.should == 2
  Notification.where(recipient_id: @users.pluck(:id)).pluck(:type).uniq.count.should == 1
  Notification.where(recipient_id: @users.pluck(:id)).pluck(:type).uniq.last.should == "InvestorKycNotification"
end


Then('I cannot send KYC reminder as no approved users are present') do
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @investor.entity, investor: @investor, verified: false)
  @investor_kyc.save(validate: false)
  entity = @investor_kyc.entity
  investor = @investor_kyc.investor
  @users = FactoryBot.create_list(:user, 2, entity: @investor.investor_entity)
  @users.each do |user|
    InvestorAccess.create!(investor: investor, user: user,
    entity_id: investor.entity_id,
    first_name: user.first_name,
    last_name: user.last_name,
    email: user.email, approved: false)
  end
  visit(investor_kyc_path(@investor_kyc))
  sleep(2)
  click_on("Send KYC Reminder")
  sleep(1)
  click_on("Proceed")
  sleep(2)
  expect(page).to have_content("KYC Reminder could not be sent as no user has been assigned to the investor")
end

Then('I select one and see the edit page and save') do
  click_on("Select CKYC Data")
  sleep(4) #image saving may take time
  click_on("Next")
  sleep(1)
  click_on("Next")
  sleep(1)
  click_on("Save")
  sleep(3)
  expect(page).to have_content("Investor kyc was successfully saved")
end


Then('when I upload the document for the kyc') do
  click_on("Actions")
  click_on("New Document")
  @document = FactoryBot.build(:document, entity: @entity, user: @entity.employees.sample)

  fill_in("document_name", with: @document.name)

  fill_in("document_tag_list", with: @document.tag_list.join(",")) if @document.tag_list.present?
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)

  sleep(3)
  click_on("Save")
  sleep(4)

end

Then('I should see the investor kyc details on the details page') do
  expect(page).to have_content(@investor_kyc.entity.name)
  expect(page).to have_content(@investor_kyc.residency.titleize)
  expect(page).to have_content(@investor_kyc.kyc_type.titleize)
  expect(page).to have_content(@investor_kyc.investor.investor_name)
  expect(page).to have_content(@investor_kyc.PAN)
  expect(page).to have_content(@investor_kyc.full_name)
  expect(page).to have_content(@investor_kyc.birth_date.strftime("%d %B, %Y")) if @investor_kyc.birth_date
  expect(page).to have_content(@investor_kyc.address)
  expect(page).to have_content(@investor_kyc.corr_address)
  expect(page).to have_content(@investor_kyc.bank_account_number)
  expect(page).to have_content(@investor_kyc.ifsc_code)
end

Given('each Investor has an approved Investor Kyc') do
  @investor_kycs = @entity.investors.each do |investor|
    kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor: investor, verified: true)
    kyc.save(validate: false)
  end
  InvestorKyc.all.each do |kyc|
    kyc.verified = true
    kyc.save(validate: false)
  end
end

Given('the fund has a SOA template {string}') do |string|
  visit(fund_path(Fund.last))
  sleep(3)
  click_on("Actions")
  click_on("New Template")
  sleep(2)
  fill_in('document_name', with: "SOA Template")
  #document_owner_tag is the type of document
  select("SOA Template", from: "document_owner_tag")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/SOA Template.docx'), make_visible: true)
  check("document_template")
  click_on("Save")
end

Given('we Generate SOA for the first capital commitment') do
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.save!
  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  click_on("Generate SOA")
  fill_in('start_date', with: "01/01/2020")
  fill_in('end_date', with: "01/01/2021")
  click_on("Generate SOA Now")
  sleep(2)
end

Then('it is successfully generated') do
  expect(page).to have_content("Generated")
  expect(page).to have_content("Documentation generation started, please check back in a few mins")
end

Then('the document has {string} e_signatures') do |string|
  allow_any_instance_of(DigioEsignHelper).to receive(:sign).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response)

  # stub DigioEsignHelper's sign method to return
  @doc = Document.order(:created_at).last
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  visit(document_path(@doc))
  sleep(2)
  click_on("Signatures")
  sleep(1)
  click_on("Send For eSignatures")
end

Then('the document has {string} e_signatures with status {string}') do |string, string2|
  allow_any_instance_of(DigioEsignHelper).to receive(:sign).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response)

  # stub DigioEsignHelper's sign method to return
  @doc = Document.order(:created_at).last
  string2 = string2 == "nil" ? nil : string2
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1, status: string2)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2, status: string2)
  visit(document_path(@doc))
  sleep(2)
  click_on("Signatures")
  sleep(1)
  click_on("Send For eSignatures")
end


Then('the document is signed by the signatories') do
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(download_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response_signed)
  visit(current_path)
  sleep(2)
  click_on("Signatures")
  sleep(1)
  click_on("Get eSignatures' updates")
end

Then('the esign completed document is present') do
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(download_response)
  visit(document_path(@doc))
  sleep(2)
  click_on("Signatures")
  sleep(1)
  # page should contain status requested
  expected_status = "Signed"
  expect(page).to have_content(expected_status)
  visit(capital_commitment_path(@capital_commitment))
  click_on("Documents")
  # the signed document owner tag will be signed
  expect(page).to have_content("Signed").once
end

Given('the fund has a Commitment template {string}') do |string|
  @fund = Fund.last
  visit(fund_path(@fund))
  sleep(3)
  click_on("Actions")
  click_on("New Template")
  sleep(2)
  fill_in('document_name', with: "Commitment Template")
  #document_owner_tag is the type of document
  select("Commitment Template", from: "document_owner_tag")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/Mutual-Confidentiality-Agreement.docx'), make_visible: true)
  check("document_template")
  click_on("Save")
  sleep(2)
  @fund.esign_emails = "shrikantgour018@gmail.com,aseemak56@yahoo.com"
  @fund.save!
  @doc = Document.where(name: "Commitment Template").last
  @template_esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, label: "Fund Signatories", position: 1, status: "")
  @template_esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, label: "Investor Signatories", position: 2, status: "")
end

Given('we Generate Commitment template for the first capital commitment') do
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.esign_emails = "testmail@testsite1.com,testmail@testsite2.com,"
  @capital_commitment.save!
  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  click_on("Generate Commitment Template")
  click_on("Proceed")
  sleep(2)
end

Then('the document has esignatures based on the template') do
  visit(capital_commitment_path(@capital_commitment))
  click_on("Documents")
  # expect generated Document
  expect(page).to have_content("Commitment Template")
  # visit the document page
  click_on("Commitment Template")
  click_on("Signatures")
  # page should contain emails of all Signatories
  @fund.esign_emails.split(",").each do |email|
    expect(page).to have_content(email)
  end
  @capital_commitment.esign_emails.split(",").each do |email|
    expect(page).to have_content(email)
  end
end

Then('the document get digio callbacks') do
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(download_response)

  @doc = Document.last
  # @doc.update_column(:provider_doc_id, "DID2312191801389959UDGNBWGRGCSC1")
  ap @doc.e_signatures.pluck(:status)
  callbacks = [digio_callback_first_signed, digio_callback_second_signed, digio_callback_first_signed, digio_callback_both_signed, digio_callback_second_signed, digio_callback_both_signed]
  callbacks.each do |cb|
    Thread.new do
      hit_signature_progress(cb)
      ap @doc.e_signatures.pluck(:status)
    end
  end
end

Then('the document is partially signed') do
  allow_any_instance_of(DigioEsignHelper).to receive(:sign).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response_first_signed)

  # stub DigioEsignHelper's sign method to return
  @doc = Document.where(name: "Commitment Template").last
  visit(document_path(@doc))
  click_on("Signatures")
  sleep(1)
  click_on("Send For eSignatures")
  sleep(2)
  visit(current_path)
  click_on("Signatures")
  sleep(1)
  click_on("Get eSignatures' updates")
  visit(current_path)
  click_on("Signatures")
  sleep(2)
  # page should contain status requested
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document esign is cancelled') do
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_cancel_esign_api).and_return(cancel_api_success_response)

  @doc = Document.where(name: "Commitment Template").last

  visit(document_path(@doc))
  click_on("Signatures")
  sleep(1)
  click_on("Cancel eSignatures")
  sleep(3)
end

Then('the document and esign status is cancelled') do
  @doc = Document.where(name: "Commitment Template").last
  visit(document_path(@doc))
  click_on("Signatures")
  sleep(1)
  expect(page).to have_content("Cancelled", minimum:3)
end

def cancel_api_success_response
  OpenStruct.new(success?: true)
end


def sample_doc_esign_init_response
  OpenStruct.new(success?: true,
    body:
  {
    "id": "DID2312191801389959UDGNBWGRGCSC1",
    "is_agreement": true,
    "agreement_type": "outbound",
    "agreement_status": "requested",
    "file_name": "Test.pdf",
    "created_at": "2021-01-04 22:23:33",
    "self_signed": false,
    "self_sign_type": "aadhaar",
    "no_of_pages": 3,
    "signing_parties": [
        {
            "name": nil,
            "status": "requested",
            "type": "self",
            "signature_type": "aadhaar",
            "identifier": "shrikantgour018@gmail.com",
            "reason": nil,
            "expire_on": "2021-01-14 23:59:59"
        },
        {
            "name": nil,
            "status": "requested",
            "type": "self",
            "signature_type": "aadhaar",
            "identifier": "aseemak56@yahoo.com",
            "reason": nil,
            "expire_on": "2021-01-14 23:59:59"
        }
      ],
      "sign_request_details": {
          "name": "Caphive",
          "requested_on": "2021-01-04 22:23:35",
          "expire_on": "2021-01-14 23:59:59",
          "identifier": "support@cahive.com",
          "requester_type": "org"
      },
    "channel": "api",
      "other_doc_details": {
          "web_hook_available": true
      },
      "access_token": {
          "created_at": "2023-01-06 12:25:32",
          "id": "GWT2301061225322132HSJY268JM2MD6",
          "entity_id": "DID210104222331448SRAQT22GMIB33B",
          "valid_till": "2023-01-06 13:25:32"
      },
      "attached_estamp_details": {}
    }.to_json
  )
end

def download_response
  OpenStruct.new(body: Document.last.file.download.read, success?: true)
end

def retrieve_signed_response
  OpenStruct.new(body:{"id"=>"DID2312191801389959UDGNBWGRGCSC1", "is_agreement"=>true, "agreement_type"=>"outbound", "agreement_status"=>"requested", "file_name"=>"Commitment with Demo Fund", "updated_at"=>"2023-12-19 18:01:39", "created_at"=>"2023-12-19 18:01:39", "self_signed"=>false, "self_sign_type"=>"aadhaar", "no_of_pages"=>10, "signing_parties"=>[{"name"=>"RON RON", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}], "sign_request_details"=>{"name"=>"Caphive", "requested_on"=>"2023-12-19 18:01:40", "expire_on"=>"2023-12-30 00:00:00", "identifier"=>"support@caphive.com", "requester_type"=>"org"}, "channel"=>"api", "other_doc_details"=>{"web_hook_available"=>true}, "attached_estamp_details"=>{}}.to_json,
  success?: true,
  signing_parties: [{"name"=>"RON RON", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}])
end

def retrieve_signed_response_signed
  OpenStruct.new(body:{"id"=>"DID2312191801389959UDGNBWGRGCSC1", "is_agreement"=>true, "agreement_type"=>"outbound", "agreement_status"=>"requested", "file_name"=>"Commitment with Demo Fund", "updated_at"=>"2023-12-19 18:01:39", "created_at"=>"2023-12-19 18:01:39", "self_signed"=>false, "self_sign_type"=>"aadhaar", "no_of_pages"=>10, "signing_parties"=>[{"name"=>"RON RON", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}], "sign_request_details"=>{"name"=>"Caphive", "requested_on"=>"2023-12-19 18:01:40", "expire_on"=>"2023-12-30 00:00:00", "identifier"=>"support@caphive.com", "requester_type"=>"org"}, "channel"=>"api", "other_doc_details"=>{"web_hook_available"=>true}, "attached_estamp_details"=>{}}.to_json,
  success?: true,
  signing_parties: [{"name"=>"RON RON", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}])
end

def retrieve_signed_response_first_signed
  OpenStruct.new(body:{"id"=>"DID2312191801389959UDGNBWGRGCSC1", "is_agreement"=>true, "agreement_type"=>"outbound", "agreement_status"=>"requested", "file_name"=>"Commitment with Demo Fund", "updated_at"=>"2023-12-19 18:01:39", "created_at"=>"2023-12-19 18:01:39", "self_signed"=>false, "self_sign_type"=>"aadhaar", "no_of_pages"=>10, "signing_parties"=>[{"name"=>"RON RON", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}], "sign_request_details"=>{"name"=>"Caphive", "requested_on"=>"2023-12-19 18:01:40", "expire_on"=>"2023-12-30 00:00:00", "identifier"=>"support@caphive.com", "requester_type"=>"org"}, "channel"=>"api", "other_doc_details"=>{"web_hook_available"=>true}, "attached_estamp_details"=>{}}.to_json,
  success?: true,
  signing_parties: [{"name"=>"RON RON", "status"=>"signed", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"shrikantgour018@gmail.com", "expire_on"=>"2023-12-30 00:00:00"}, {"name"=>"Charley Emmerich1", "status"=>"requested", "updated_at"=>"2023-12-19 18:01:39", "type"=>"self", "signature_type"=>"electronic", "signature_mode"=>"slate", "identifier"=>"aseemak56@yahoo.com", "expire_on"=>"2023-12-30 00:00:00"}])
end

def hit_signature_progress(payload)
  url = URI.parse('http://localhost:3000/documents/signature_progress')
  http = Net::HTTP.new(url.host, url.port)

  # Create a request
  request = Net::HTTP::Post.new(url.path,
  {'Content-Type' => 'application/json', 'Accept' => 'application/json'})
  request.body = payload
  response = http.request(request)
  puts response.body
  response
end

def digio_callback_first_signed
  {"entities":["document"],"payload":{"document":{"updated_at":1703164607000,"sign_request_details":{"identifier":"support@caphive.com","expire_on":1704047400000,"name":"Caphive","requested_on":1703164608000,"requester_type":"org"},"attached_estamp_details":{},"file_name":"commitment with Demo fund","agreement_status":"requested","id":"DID2312191801389959UDGNBWGRGCSC1","signing_parties":[{"has_dependents":nil,"signature_mode":"slate","identifier":"shrikantgour018@gmail.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"shrikantgour018@gmail.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"signed"},{"has_dependents":nil,"signature_mode":"slate","identifier":"aseemak56@yahoo.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"aseemak56@yahoo.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"requested"}],"others":{"last_signed_by":"shrikantgour018@gmail.com","has_all_signed":false}}},"created_at":1703164687000,"id":"WHN2312211848066346G2QY1F19GZC15","event":"doc.signed"}.to_json
end

def digio_callback_second_signed
  {"entities":["document"],"payload":{"document":{"updated_at":1703164607000,"sign_request_details":{"identifier":"support@caphive.com","expire_on":1704047400000,"name":"Caphive","requested_on":1703164608000,"requester_type":"org"},"attached_estamp_details":{},"file_name":"commitment with Demo fund","agreement_status":"requested","id":"DID2312191801389959UDGNBWGRGCSC1","signing_parties":[{"has_dependents":nil,"signature_mode":"slate","identifier":"shrikantgour018@gmail.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"shrikantgour018@gmail.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"requested"},{"has_dependents":nil,"signature_mode":"slate","identifier":"aseemak56@yahoo.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"aseemak56@yahoo.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"signed"}],"others":{"last_signed_by":"aseemak56@yahoo.com","has_all_signed":false}}},"created_at":1703164687000,"id":"WHN2312211848066346G2QY1F19GZC15","event":"doc.signed"}.to_json
end

def digio_callback_both_signed
  {"entities":["document"],"payload":{"document":{"updated_at":1703164607000,"sign_request_details":{"identifier":"support@caphive.com","expire_on":1704047400000,"name":"Caphive","requested_on":1703164608000,"requester_type":"org"},"attached_estamp_details":{},"file_name":"commitment with Demo fund","agreement_status":"requested","id":"DID2312191801389959UDGNBWGRGCSC1","signing_parties":[{"has_dependents":nil,"signature_mode":"slate","identifier":"shrikantgour018@gmail.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"shrikantgour018@gmail.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"signed"},{"has_dependents":nil,"signature_mode":"slate","identifier":"aseemak56@yahoo.com","reason":nil,"type":"self","aadhaar_mode":nil,"signature_type":"electronic","signing_index":nil,"updated_at":1703164607000,"sign_coordinates":nil,"expire_on":1704047400000,"signature_verification_response":nil,"name":"aseemak56@yahoo.com","skip_primary_sign":nil,"pki_signature_details":nil,"dependents":nil,"next_dependent":nil,"review_comment":nil,"status":"requested"}],"others":{"last_signed_by":"shrikantgour018@gmail.com","has_all_signed":true}}},"created_at":1703164687000,"id":"WHN2312211848066346G2QY1F19GZC15","event":"doc.signed"}.to_json
end


Given('the fund has a KYC template {string}') do |string|
  pending # Write code here that turns the phrase above into concrete actions
end

Given('we Generate KYC template for the first KYC') do
  pending # Write code here that turns the phrase above into concrete actions
end
