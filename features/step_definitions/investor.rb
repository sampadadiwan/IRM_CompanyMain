require 'cucumber/rspec/doubles'
require 'net/http'
require 'uri'

Given('I am at the investor page') do
  visit("/investors")
end

Given('the esign provider is {string}') do |esign_provider|
  entity_setting = @entity.entity_setting
  entity_setting.update(esign_provider: esign_provider)
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
  # fill_in('investor_pan', with: @investor.pan)
  select("Founder", from: "investor_category")
  fill_in('investor_tag_list', with: @investor.tag_list)
  # fill_in('investor_primary_email', with: @investor_entity.primary_email)

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
  
  @investor_entity.reload
end


Given('the existing investor user has role {string}') do |role|
  @employee_investor.add_role(role)
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
  @portfolio_company = @investor
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

Given('there are {string} existing investor {string} with {string} users') do |count, arg1, emp_count|
  (1..count.to_i).each do
    steps %(
      Given there is an existing investor "#{arg1}" with "#{emp_count}" users
    )
  end
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

  visit(investor_path(Investor.first))
  find("#stakeholder_users_tab").click
  find("#upload_stakeholder_users").click

  fill_in('import_upload_name', with: "Test Investor Access Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('the investor accesses must have the data in the sheet') do
  file = File.open('./public/sample_uploads/investor_access.xlsx', "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

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
    ia.whatsapp_enabled.should == (user_data["Whatsapp Enabled"] == "Yes" ? true : false)
    ia.import_upload_id.should == ImportUpload.last.id
  end

end


Given('Given I upload an investor kyc {string} for employees') do |file_name|
  visit(investor_kycs_path)
  click_on("Upload/Download")
  click_on("Upload KYC Details")
  fill_in('import_upload_name', with: "Test Investor Access Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end


Then('There should be {string} investor access created') do |count|
  InvestorAccess.count.should == count.to_i
  InvestorAccess.all.each do |ia|
    # Now ia.whatsapp_enabled can be different from user.whatsapp_enabled and both need to be set to send WA
    # ia.whatsapp_enabled.should == ia.user.whatsapp_enabled
    ia.user.whatsapp_enabled.should == true
    puts "Checking import of #{ia.first_name} #{ia.last_name} #{ia.email} #{ia.phone} #{ia.approved} #{ia.whatsapp_enabled}"
    ia.first_name.should == ia.user.first_name
    ia.last_name.should == ia.user.last_name
    ia.phone.should == ia.user.phone
    ia.email.should == ia.user.email
  end
end

Given('Given I upload an investors file large for the fund') do
    visit(investors_path)
    click_on("Actions")
    click_on("Upload")
    #sleep(3)
    fill_in('import_upload_name', with: "Test Investor Upload")
    attach_file('files[]', File.absolute_path('./public/sample_uploads/investors-large.xlsx'), make_visible: true)
    sleep(2)
    click_on("Save")
    #sleep(5)
    expect(page).to have_content("Import Upload:")
    ImportUploadJob.perform_now(ImportUpload.last.id)
    #sleep(4)
end

Given('Given I upload an investors file for the company') do
  visit(investors_path)
  click_on("Actions")
  click_on("Upload")
  #sleep(1)
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investors.xlsx'), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep(3)
end

Given('the investors have approved investor access') do
  @entity.investors.each do |investor|
    ia = FactoryBot.create(:investor_access, investor: investor, entity: investor.entity, approved: true)
  end
end

Then('There should be {string} investors created') do |count|
  @entity.investors.count.should == count.to_i
end

Then('the investors must have the data in the sheet') do
  file = File.open('./public/sample_uploads/investors.xlsx', "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  investors = @entity.investors.order(id: :asc).to_a
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
  #sleep(1)
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/fund_investors.xlsx'), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('the investors must be added to the fund') do
  @fund.reload
  # puts @fund.investors.to_json
  investors = @entity.investors.to_set
  fund_investors = @fund.investors.to_set
  investors.length.should == fund_investors.length

  investors.should == fund_investors

end

Then('There should be {string} investor kycs created') do |count|
  @entity.investor_kycs.count.should == count.to_i
end

Then('the investor kycs must have the data in the sheet {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  investor_kycs = @entity.investor_kycs.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = investor_kycs[idx-1]
    ap cc

    puts "Checking import of #{cc.full_name} #{cc.class.name}}"
    if user_data["Investing Entity"].present?
      cc.full_name.should == user_data["Investing Entity"]
      cc.birth_date.to_date.should == user_data["Date Of Birth"]
      cc.address.should == user_data["Address"]
      cc.corr_address.should == user_data["Correspondence Address"]
      cc.PAN.should == user_data["Pan"]
      cc.bank_name.should == user_data["Bank Name"]
      cc.bank_branch.should == user_data["Branch Name"]
      cc.bank_account_number.should == user_data["Bank Account Number"]&.to_s
      cc.ifsc_code.should == user_data["Ifsc Code"]&.to_s
      cc.esign_emails.should == user_data["Investor Signatory Emails"]
      cc.agreement_committed_amount.to_d.should == user_data["Agreement Committed Amount"]&.to_d || 0
      cc.agreement_unit_type.should == user_data["Agreement Unit Type"]
      cc.import_upload_id.should == ImportUpload.last.id unless user_data["Update Only"] != "Yes"
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
  allow_any_instance_of(KycVerify).to receive(:search_ckyc).and_return(OpenStruct.new(parsed_response:{"success": true}))
  allow_any_instance_of(KycVerify).to receive(:download_ckyc_response).and_return(sample_ckyc_download_response)
  visit(investor_kycs_path)
  #sleep(2)
  click_on("New KYC")
  click_on("Individual")
  #sleep(2)
  class_name = "individual_kyc" #@investor_kyc.type_from_kyc_type.underscore
  fill_in("#{class_name}_birth_date", with: Date.today - 20.years)
  fill_in("#{class_name}_PAN", with: "PANNUMBER1")
  click_on("Next")
  #sleep(4)
end

Given('I create a new InvestorKyc {string} with files {string} for {string}') do |args, files, kyc_url_params|

  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity)
  files = files.downcase
  key_values(@investor_kyc, args)
  # InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user: false)
  puts "\n########### KYC ############"
  puts @investor_kyc.to_json

  class_name = @investor_kyc.type_from_kyc_type.underscore

  if kyc_url_params.present?
    # For Investors create thier own KYC
    visit(new_investor_kyc_path(eval(kyc_url_params)))
  else
    # For Funds creating KYCs
    visit(investor_kycs_path)
    click_on("New KYC")
    click_on("Individual")
    #sleep(2)
    select(@investor_kyc.investor.investor_name, from: "#{class_name}_investor_id")
  end

  if files.include?("pan")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_upload_pan' do
        click_on 'Choose file'
      end
    end
  end
  sleep(4)

  fill_in("#{class_name}_full_name", with: @investor_kyc.full_name)
  select(@investor_kyc.residency.titleize, from: "#{class_name}_residency")
  fill_in("#{class_name}_PAN", with: @investor_kyc.PAN)
  fill_in("#{class_name}_birth_date", with: @investor_kyc.birth_date)
  click_on("Next")
  #sleep(3)


  if files.include?("address proof")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_upload_address_proof' do
        click_on 'Choose file'
      end
    end
  end
  if files.include?("cancelled cheque")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_upload_cancelled_cheque_bank_statement' do
        click_on 'Choose file'
      end
    end
  end
  sleep(2)

  fill_in("#{class_name}_address", with: @investor_kyc.address)
  fill_in("#{class_name}_corr_address", with: @investor_kyc.corr_address)
  fill_in("#{class_name}_bank_name", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_branch", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_account_number", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_ifsc_code", with: @investor_kyc.ifsc_code)
  click_on("Next")
  #sleep(1)

  unless kyc_url_params.present?
    fill_in("#{class_name}_expiry_date", with: @investor_kyc.expiry_date)
    fill_in("#{class_name}_comments", with: @investor_kyc.comments)
  end

  if files.include?("f1")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_f1' do
        click_on 'Choose file'
      end
    end
  end

  if files.include?("f2")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_f2' do
        click_on 'Choose file'
      end
    end
  end
  sleep(2)

  if args.include?("properties")
    @investor_kyc.properties.each do |key, value|
      name = FormCustomField.to_name(key)
      fill_in("#{class_name}_properties_#{name}", with: value)
    end
  end

  click_on("Save")
  #sleep(1)
  expect(page).to have_content("successfully")

end

Then('I should see the kyc documents {string}') do |docs|
  @investor_kyc = InvestorKyc.last
  document_names = @investor_kyc.documents.pluck(:name)
  docs.split(",").each do |doc_name|
    puts "Checking for #{doc_name}"
    document_names.include?(doc_name).should == true
  end
end

Given('the entity has custom fields {string} for {string}') do |args, class_name|
  puts "Creating custom fields for #{class_name} #{args.split('#')}"
  ft = @entity.form_types.create!(name: class_name)
  args.split("#").each do |arg|
    cf = ft.form_custom_fields.build()
    key_values(cf, arg)
    cf.save!
  end
end

Then('I should see ckyc and kra data comparison page') do
  expect(page).to have_content("CKYC")
  expect(page).to have_content("KRA")
end

Then('I can send KYC reminder to approved users') do
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @investor.entity, investor: @investor, verified: false)
  InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user: false)
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
  #sleep(2)
  click_on("Send KYC Reminders")
  #sleep(1)
  click_on("Proceed")
  #sleep(2)
  expect(page).to have_content("KYC Reminder sent successfully")
end

Then('Notifications are created for KYC Reminders') do
  Noticed::Notification.where(recipient_id: @users.pluck(:id)).count.should == 2
  Noticed::Notification.where(recipient_id: @users.pluck(:id)).pluck(:type).uniq.count.should == 1
  Noticed::Notification.where(recipient_id: @users.pluck(:id)).pluck(:type).uniq.last.should == "InvestorKycNotifier::Notification"
end


Then('I cannot send KYC reminder as no approved users are present') do
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @investor.entity, investor: @investor, verified: false)
  InvestorKycCreate.call(investor_kyc: @investor_kyc, investor_user: false)
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
  #sleep(2)
  click_on("KYC Actions")
  click_on("Send KYC Reminder")
  #sleep(1)
  click_on("Proceed")
  #sleep(2)
  expect(page).to have_content("KYC Reminder could not be sent as no user has been assigned to the investor")
end

Then('I select one and see the edit page and save') do
  click_on("Select CKYC Data")
  #sleep(4) #image saving may take time
  click_on("Next")
  #sleep(1)
  click_on("Next")
  #sleep(1)
  click_on("Save")
  #sleep(3)
  expect(page).to have_content("Investor kyc was successfully saved")
end

Given('there are {string} investors') do |count|
  (0..count.to_i-1).each do
    e = FactoryBot.create(:entity, entity_type: "Investor")
    FactoryBot.create(:investor, entity: e)
  end
end

Then('when I upload the document for the kyc') do
  within("#docs_index") do
    click_on("Actions")
  end
  click_on("New Document")
  @document = FactoryBot.build(:document, entity: @entity, user: @entity.employees.sample)

  fill_in("document_name", with: @document.name)

  fill_in("document_tag_list", with: @document.tag_list.join(",")) if @document.tag_list.present?
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)

  #sleep(3)
  click_on("Save")
  expect(page).to have_content("successfully")
  #sleep(4)

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

Given('the fund has a template {string} of type {string}') do |name, owner_tag|
  @template_name = name
  visit(fund_path(Fund.last))
  sleep(3)
  click_on("Actions")
  sleep(0.5)
  find('#misc_action_menu').hover
  sleep(2)
  click_on("New Template")
  #sleep(2)
  fill_in('document_name', with: name)

  select(owner_tag, from: "document_owner_tag")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{name}.docx"), make_visible: true)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  sleep(5)
  check("document_template")
  click_on("Save")
  expect(page).to have_content("successfully")
  #sleep(2)
end

Given('we Generate SOA for the first capital commitment') do
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.save!
  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  #sleep(1)
  click_on("Generate SOA")
  @start_date = Date.parse "01/01/2020"
  @end_date = Date.parse "01/01/2021"
  fill_in('start_date', with: @start_date)
  fill_in('end_date', with: @end_date)
  #sleep(1)
  click_on("Generate SOA Now")
  #sleep(2)
end

Then('we Generate SOA for the first capital commitment again') do
  @og_soa_created_at = @capital_commitment.documents.generated.last.created_at
  steps %(
    Given we Generate SOA for the first capital commitment
  )
end

Then('we Generate SOA for the first capital commitment with different time') do
  @og_soa_created_at = @capital_commitment.documents.generated.last.created_at
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.save!
  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  #sleep(1)
  click_on("Generate SOA")
  @start_date = Date.parse "01/02/2020"
  @end_date = Date.parse "01/02/2021"
  fill_in('start_date', with: @start_date)
  fill_in('end_date', with: @end_date)
  click_on("Generate SOA Now")
end

Then('the unapproved SOA is replaced') do
  expect(@capital_commitment.documents.generated.last.created_at).to be > @og_soa_created_at
end

Given('the generated SOA is approved') do
  @generated_soa = @capital_commitment.documents.generated.last
  @generated_soa.approved = true
  @generated_soa.save!
end

Given('we Generate Commitment Agreement for the first capital commitment') do
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.save!

  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  click_on("Generate #{@template_name}")
  #sleep(2)
  click_on("Proceed")
  #sleep(2)
end

Then('we Generate Commitment Agreement for the first capital commitment with corrupt {string}') do |string|
  steps %(
    Then we Generate Commitment Agreement for the first capital commitment again
  )
  sleep 3
end


Then('we Generate Commitment Agreement for the first capital commitment again') do
  @original_doc = Document.where(owner_tag: "Generated").last
  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  click_on("Generate #{@template_name}")
  click_on("Proceed")
end

Given('the commitment has a corrupted footer for the template') do
  Document.create!(entity: @capital_commitment.entity, name: "#{@template_name} Footer",
  text: Faker::Company.catch_phrase, user: @user, owner: @capital_commitment,
  folder: @capital_commitment.document_folder, file: File.new("public/sample_uploads/corrupt.pdf", "r"))
end

Given('the commitment has a corrupted header for the template') do
  Document.create!(entity: @capital_commitment.entity, name: "#{@template_name} Header",
  text: Faker::Company.catch_phrase, user: @user, owner: @capital_commitment,
  folder: @capital_commitment.document_folder, file: File.new("public/sample_uploads/corrupt.pdf", "r"))
end

Then('the original document is replaced') do
  @generated_doc = Document.where(owner_tag: "Generated").last
  @generated_doc.should_not == @original_doc
  @generated_doc.created_at.should > @original_doc.created_at
end

Then('the last generated document is approved') do
  @doc = Document.where(owner_tag: "Generated").last
  @doc.approved = true
  @doc.save!
end

Given('we Generate All Documents for the first capital commitment') do
  @capital_commitment = CapitalCommitment.last
  @capital_commitment.investor_kyc = InvestorKyc.last
  @capital_commitment.save!

  visit(capital_commitment_path(@capital_commitment))
  find("#commitment_actions").click
  click_on("Generate All Documents")
  click_on("Proceed")
end

Then('we get the email with error {string}') do |error|
  sleep(1)
  @user = User.first
  current_email = nil
  emails_sent_to(@user.email).each do |email|
    puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
    current_email = email if email.subject == "Errors"
  end
  expect(current_email.body).to include error
end

Then('we get the email with approved document exists error') do
  error = "Approved document already exists for  #{@capital_commitment.investor_kyc.full_name} - #{@capital_commitment.folio_id} with template #{@template_name}"
  steps %(
    Then we get the email with error "#{error}"
  )
end


Then('the {string} is successfully generated') do |name|
  expect(page).to have_content("Documentation generation started, please check back in a few mins")
  #sleep(2)
  visit(current_url)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content("Generated")
  generated_doc = Document.where(owner_tag: "Generated").last
  if name.include?("SOA")
    generated_doc.name.should == "#{name} #{@start_date.strftime("%d %B,%Y")} to #{@end_date.strftime("%d %B,%Y")} - #{@capital_commitment}"
  else
    generated_doc.name.should == "#{name} - #{@capital_commitment}"
  end
  generated_doc.name.include?(name).should == true
  generated_doc.name.include?(@capital_commitment.investor_kyc.full_name).should == true
end

Then('the document has {string} e_signatures') do |string|
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response)
  # stub DigioEsignHelper's sign method to return
  @doc = Document.order(:created_at).last
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  visit(document_path(@doc))
  #sleep(2)
  click_on("Signatures")
  #sleep(1)
  click_on("Send For eSignatures")
  sleep(4)
end

Then('the document has {string} e_signatures by Docusign') do |string|
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_envelope).and_return(docusign_get_envelope)
  allow_any_instance_of(ApiCreator).to receive(:create_envelope_api).and_return(docusign_envelope_api)
  allow_any_instance_of(DocusignEsignHelper).to receive(:send_document_for_esign).and_return(sample_docusign_esign_init_response)
  @doc = Document.order(:created_at).last
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_recipients).and_return(docusign_envelope_recipients_api(["sent", "sent"], ESignature.pluck(:email)))
  # stub DigioEsignHelper's sign method to return
  visit(document_path(@doc))
  #sleep(2)
  click_on("Signatures")
  #sleep(1)
  click_on("Send For eSignatures")
  #sleep(2)
  visit(document_path(@doc))
end

Then('when the document is approved') do
  @doc = Document.last
  @doc.approved = true
  @doc.save!
end

Then('the document has {string} e_signatures with status {string}') do |string, string2|
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response)

  # stub DigioEsignHelper's sign method to return
  @doc = Document.order(:created_at).last
  string2 = string2 == "nil" ? nil : string2
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1, status: string2)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2, status: string2)
  visit(document_path(@doc))
  #sleep(2)
  click_on("Signatures")
  #sleep(1)
  click_on("Send For eSignatures")
end


Then('the document is signed by the signatories') do
  allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(download_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response_signed)

  sleep(3)
  visit(current_path)
  # sleep(2)
  click_on("Signatures")
  # sleep(1)
  click_on("Get eSignatures' updates")
end

Then('the document is signed by the docusign signatories') do
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_envelope).and_return(docusign_get_envelope)
  allow_any_instance_of(ApiCreator).to receive(:create_envelope_api).and_return(docusign_envelope_api)
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_recipients).and_return(docusign_envelope_recipients_api(["completed", "completed"], ESignature.pluck(:email)))
  allow_any_instance_of(DocusignEsignHelper).to receive(:download).and_return(docusign_download_response)
  sleep(5)
  visit(current_url)
  #sleep(3)
  click_on("Signatures")
  #sleep(2)
  # click_on("Get eSignatures' updates")
end

Then('the esign completed document is present') do
  # allow_any_instance_of(DigioEsignHelper).to receive(:download).and_return(download_response)
  @doc = Document.where(owner_tag: "Generated").last
  sleep(4)
  visit(document_path(@doc))
  sleep(1)
  click_on("Signatures")
  expected_status = "Signed"
  expect(page).to have_content(expected_status)
  visit(capital_commitment_path(@capital_commitment))
  # click_on("Documents")
  # the signed document owner tag will be signed
  expect(page).to have_content("Signed").once
end

Then('the docusign esign completed document is present') do
  allow_any_instance_of(ApiCreator).to receive(:create_envelope_api).and_return(docusign_envelope_api)
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_recipients).and_return(docusign_envelope_recipients_api(["completed", "completed"], ESignature.pluck(:email), "completed"))
  allow_any_instance_of(DocusignEsignHelper).to receive(:download).and_return(docusign_download_response)
  click_on("Get eSignatures' updates")
  sleep(2)
  visit(document_path(@doc))
  #sleep(1)
  # page should contain status signed
  click_on("Signatures")
  expected_status = "Signed"
  expect(page).to have_content(expected_status)
  visit(capital_commitment_path(@capital_commitment))
  xpath = "/html/body/div[2]/div[1]/div/div/div[7]/nav/a[1]"
  documents_button = find(:xpath, xpath)
  documents_button.click
  # the signed document owner tag will be signed
  expect(page).to have_content("Signed").once
end

Given('the template has esigns setup') do
  @fund.esign_emails = "shrikantgour018@gmail.com,aseemak56@yahoo.com"
  @fund.save!

  @doc = Document.where(template: true).last
  @template_esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, label: "Fund Signatories", position: 1, status: "")
  @template_esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, label: "Investor Signatories", position: 2, status: "")
end

Then('the document has esignatures based on the template') do
  visit(capital_commitment_path(@capital_commitment))
  # click_on("Documents")
  # expect generated Document
  expect(page).to have_content(@template_name)
  # visit the document page
  click_on(@template_name)
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
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response_first_signed)

  visit(document_path(@doc))
  click_on("Signatures")
  #sleep(1)
  click_on("Send For eSignatures")
  sleep(3)
  visit(current_path)
  click_on("Signatures")
  #sleep(1)
  click_on("Get eSignatures' updates")
  visit(current_path)
  click_on("Signatures")
  #sleep(2)
  # page should contain status requested
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document is partially signed by Docusign') do
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_envelope).and_return(docusign_get_envelope)
  allow_any_instance_of(ApiCreator).to receive(:create_envelope_api).and_return(docusign_envelope_api)
  allow_any_instance_of(DocusignEsignHelper).to receive(:send_document_for_esign).and_return(sample_docusign_esign_init_response)
  @doc = Document.order(:created_at).last
  @esign1 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "shrikantgour018@gmail.com", position: 1)
  @esign2 = FactoryBot.create(:e_signature, document: @doc, entity: @doc.entity, email: "aseemak56@yahoo.com", position: 2)
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_recipients).and_return(docusign_envelope_recipients_api(["completed", "sent"], ESignature.pluck(:email)))
  visit(document_path(@doc))
  #sleep(2)
  click_on("Signatures")
  #sleep(1)
  click_on("Send For eSignatures")
  sleep(2)
  visit(document_path(@doc))
  visit(current_path)
  click_on("Signatures")
  #sleep(1)
  click_on("Get eSignatures' updates")
  sleep(8)
  visit(current_path)
  click_on("Signatures")
  # page should contain status requested
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document esign is cancelled') do
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_cancel_esign_api).and_return(cancel_api_success_response)

  visit(document_path(@doc))
  click_on("Signatures")
  #sleep(1)
  click_on("Cancel eSignatures")
  #sleep(3)
end

Then('the docusign document esign is cancelled') do
  allow_any_instance_of(DocusignEsignHelper).to receive(:cancel_docusign_api).and_return(cancel_docusign_api_response)

  visit(document_path(@doc))
  click_on("Signatures")
  #sleep(1)
  click_on("Cancel eSignatures")
  sleep(3)
  expect(@doc.reload.esign_status.downcase).to(eq("cancelled"))
end

Then('the document can be resent for esign') do
  allow_any_instance_of(DigioEsignHelper).to receive(:hit_digio_esign_api).and_return(sample_doc_esign_init_response)
  allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed).and_return(retrieve_signed_response_first_signed)

  #sleep(2)
  expect(page).to have_content("Re-Send for eSignatures")
  click_on("Re-Send for eSignatures")
  sleep(2)
  visit(current_path)
  click_on("Signatures")
  #sleep(1)
  click_on("Get eSignatures' updates")
  visit(current_path)
  click_on("Signatures")
  #sleep(2)
  # page should contain status requested
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the docusign document can be resent for esign') do
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_envelope).and_return(docusign_get_envelope)
  allow_any_instance_of(ApiCreator).to receive(:create_envelope_api).and_return(docusign_envelope_api)
  allow_any_instance_of(DocusignEsignHelper).to receive(:send_document_for_esign).and_return(sample_docusign_esign_init_response)
  allow_any_instance_of(DocusignEsignHelper).to receive(:get_recipients).and_return(docusign_envelope_recipients_api(["completed", "sent"], ESignature.pluck(:email)))

  #sleep(2)
  expect(page).to have_content("Re-Send for eSignatures")
  click_on("Re-Send for eSignatures")
  sleep(3)
  visit(current_path)
  click_on("Signatures")
  #sleep(1)
  click_on("Get eSignatures' updates")
  sleep(4)
  visit(current_path)
  click_on("Signatures")
  # page should contain status requested
  expect(page).to have_content("Requested")
  expect(page).to have_content("Signed")
end

Then('the document and esign status is cancelled') do
  visit(document_path(@doc))
  click_on("Signatures")
  #sleep(1)
  expect(page).to have_content("Cancelled", minimum:3)
end

def cancel_api_success_response
  OpenStruct.new(success?: true)
end

def sample_docusign_esign_init_response
  {"envelope_id": SecureRandom.uuid}
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

def docusign_download_response
  Document.last.file.download
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

def docusign_retrieve_signed_response_first_signed
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

def sample_ckyc_search_response
  {
    success: true,
    search_response: {
      ckyc_number: "{CKYC Number Here}",
      name: "MR DINESH  RATHORE ",
      fathers_name: "Mr TEJA  RAM RATHORE",
      age: "30",
      image_type: "jpg",
      photo: "{Base64 Value of Image}",
      kyc_date: "08-04-2017",
      updated_date: "08-04-2017",
      remarks: ""
    }
  }
end

def sample_err_response
  {
    success: false,
    error_message: "{Error Message}"
  }
end

def sample_ckyc_download_response
  {
    success: true,
    download_response: {
      personal_details: {
        ckyc_number: Faker::Number.number(digits: 12), type: "INDIVIDUAL/CORP/HUF etc", kyc_type: "normal/ekyc/minor", prefix: "MR", first_name: Faker::Name.first_name, middle_name: Faker::Name.middle_name, last_name: Faker::Name.last_name, full_name: Faker::Name.name, maiden_prefix: "", maiden_first_name: "", maiden_middle_name: "", maiden_last_name: "", maiden_full_name: "", father_spouse_flag: "father/spouse", father_prefix: "Mr", father_first_name: "TEJA", father_middle_name: "", father_last_name: "RAM RATHORE", father_full_name: "Mr TEJA  RAM RATHORE", mother_prefix: "Mrs", mother_first_name: "", mother_middle_name: "", mother_last_name: "", mother_full_name: "", gender: "M", dob: "{}", pan: Faker::Number.number(digits: 10), perm_address_line1: "BERA NAVODA", perm_address_line2: "BER KALAN", perm_address_line3: "JAITARAN", perm_address_city: "JAITARAN", perm_address_dist: "Pali", perm_address_state: "RJ", perm_address_country: "IN", perm_address_pincode: "306302", perm_current_same: "Y/N", corr_address_line1: "BERA NAVODA", corr_address_line2: "BER KALAN", corr_address_line3: "JAITARAN", corr_address_city: "JAITARAN", corr_address_dist: "Pali", corr_address_state: "RJ", corr_address_country: "IN", corr_address_pincode: "306302", mobile_no: Faker::Number.number(digits: 10), email: Faker::Internet.email, date: "02-04-2017", place: "Bangalore"
      },
      id_details: [
        {
          type: "PAN", id_no: Faker::Number.number(digits: 10), ver_status: true
        }
      ],
      images: [
        {
          image_type: "PHOTO", type: "jpg/pdf", data: Base64.strict_encode64(File.read("public/img/logo_big.png"))
        },
        {
          image_type: "PAN", type: "jpg/pdf", data: Base64.encode64(File.read("public/img/whatsappQR.png"))
        },
        {
          image_type: "AADHAAR/PASSPORT/VOTER/DL", type: "jpg/pdf", data: Base64.encode64(File.read("public/img/logo_trans.png"))
        },
        {
          image_type: "SIGNATURE", type: "jpg/pdf", data: Base64.encode64(File.read("public/img/logo_trans.old.png"))
        }
      ]
    }
  }
end

def sample_kra_pan_data
  {
    result: "FOUND",
    pan_number: Faker::Number.number(digits: 10),
    name: Faker::Name.name,
    status: "KRA Verified",
    status_date: "29-04-2017 16:16:45",
    entry_date: "12-04-2017 12:30:16",
    modification_date: "",
    kyc_mode: "Normal KYC",
    deactivate_remarks: "",
    update_remarks: "",
    ipv_flag: "Y",
    pan_details: {
      pan_number: Faker::Number.number(digits: 10), dob: "05/07/1990", gender: "M", name: Faker::Name.name, father_name: Faker::Name.name, correspondence_address1: "", correspondence_address2: "", correspondence_address3: "JAITARAN", correspondence_city: "PALI", correspondence_pincode: "306302", correspondence_state: "Rajasthan", correspondence_country: "India", correspondence_address_proof: "Id Type", correspondence_address_proof_ref: "Id Number", correspondence_address_proof_date: "",
      mobile_number: Faker::Number.number(digits: 10),
      email_address: Faker::Internet.email, permanent_address1: "", permanent_address2: "", permanent_address3: "JAITARAN", permanent_city: "PALI", permanent_pincode: "306302", permanent_state: "Rajasthan", permanent_country: "India", permanent_address_proof: "Id type", permanent_address_proof_ref: "Id Number", permanent_address_proof_date: "", income: "> 25 LAC", occupation: "PRIVATE SECTOR SERVICE", political_connection: "NA", resident_status: "R", nationality: "Indian", ipv_date: "29/03/2017"
    }
  }
end


Given('the investor entity has no {string} permissions') do |perm|
  @investor.investor_entity.permissions.unset(perm.to_sym)
  @investor.investor_entity.save!
  ap @investor.investor_entity.permissions
end

Given('a InvestorKyc is created with details {string} by {string}') do |args, investor_user|
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity, investor: @investor)
  key_values(@investor_kyc, args)
  investor_user = investor_user == "true"
  InvestorKycCreate.wtf?(investor_kyc: @investor_kyc, investor_user:).success?.should == true
end

Given('I visit the investor kyc page') do
  visit(investor_kyc_path(@investor_kyc))
end

Then('the kyc form should be sent {string} to the investor') do |flag|
  user = InvestorAccess.includes(:user).first.user
  open_email(user.email)
  if flag == "true"
    expect(current_email.subject).to include "Request to add KYC: #{@investor_kyc.entity.name}"
  else
    current_email.should == nil
  end
end


Then('the kyc form reminder should be sent {string} to the investor') do |flag|
  user = InvestorAccess.includes(:user).first.user
  open_email(user.email)
  if flag == "true"
    expect(current_email.subject).to include "Reminder to update KYC: #{@investor_kyc.entity.name}"
  else
    current_email.should == nil
  end
end

Given('there is a custom notification {string} in place for the KYC') do |args|
  @custom_notification = CustomNotification.build(entity: @entity, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), for_type: "InvestorKyc", owner: @entity)
  key_values(@custom_notification, args)
  @custom_notification.save!
end

Then('the first notification has latest {string} and enable {string}') do |latest, enabled|
  CustomNotification.first.latest.to_s.should == latest
  CustomNotification.first.enabled.to_s.should == enabled
end

Then('the second notification has latest {string} and enable {string}') do |latest, enabled|
  CustomNotification.last.latest.to_s.should == latest
  CustomNotification.last.enabled.to_s.should == enabled
end


Then('the investor entity should have {string} permissions') do |args|
  @investor.reload
  @investor.investor_entity.permissions.set?(args.to_sym).should == true
end

Then('the aml report should be generated for the investor kyc') do
  AmlReport.first.should_not == nil
end

Then('notification should be sent {string} to the employee for kyc update') do |sent|
  user = @entity.employees.first
  open_email(user.email)
  puts "Checking email for #{user.email} sent #{sent}"

  if sent == "true"
    expect(current_email.subject).to include "KYC updated for #{@investor_kyc.full_name}"
  else
    current_email.should == nil
  end
end

Given('notification should be sent {string} to the investor for {string}') do |sent, cn_args|
  cn = CustomNotification.new
  key_values(cn, cn_args)
  user = InvestorAccess.includes(:user).first.user
  open_email(user.email)
  puts "Checking email for #{user.email} with email_method: #{cn.email_method}, subject: #{current_email&.subject}"
  if sent == "true"
    expect(current_email.subject).to include @entity.custom_notification(cn.email_method).subject
    clear_emails
  else
    current_email.should == nil
  end

end

Given('notification should be sent {string} to the user for {string}') do |sent, cn_args|
  cn = CustomNotification.new
  key_values(cn, cn_args)
  user = @entity.employees.first
  open_email(user.email)
  puts "Checking email for #{user.email} with email_method: #{cn.email_method}, subject: #{current_email&.subject}"
  if sent == "true"
    expect(current_email.subject).to include @entity.custom_notification(cn.email_method).subject
    clear_emails
  else
    current_email.should == nil
  end
end

Given('the kyc reminder is sent to the investor') do
  @entity.reload.investor_kycs.each do |kyc|
    kyc.send_kyc_form(reminder: true)
  end
end



Then('when I Send KYC reminder for the kyc') do
  # clear_emails
  visit(investor_kyc_path(@investor_kyc))
  click_on("KYC Actions")
  click_on("Send KYC Reminder")
  click_on("Proceed")
end


Given('I filter the kycs by {string}') do |args|
end


Then('the kycs should be verified') do
  InvestorKyc.where(verified: false).count.should == 0
end

Then('the kycs should be unverified') do
  InvestorKyc.where(verified: true).count.should == 0
end

Then('the kycs users should receive the kyc reminder email') do
  InvestorKyc.where(verified: false).each do |kyc|
    kyc.investor.investor_accesses.approved.each do |ia|
      puts "Checking email for #{ia.email}"
      open_email(ia.email)
      expect(current_email.subject).to include "Reminder to update KYC: #{kyc.entity.name}"
    end
  end
end

def docusign_envelope_api
  OpenStruct.new(api_client: "")
end

def docusign_envelope_recipients_api(recipient_statuses, emails, envelope_status = "sent")
  OpenStruct.new(signers: docusign_list_recipients(recipient_statuses, emails), get_envelope: docusign_get_envelope(envelope_status))
end

def docusign_list_recipients(statuses, emails)
  statuses.zip(emails).map do |status, email|
    OpenStruct.new(status: status, email: email)
  end
end

def docusign_get_envelope(status = "sent")
  OpenStruct.new(envelope: "Sample envelope", status: status)
end

def cancel_docusign_api_response
  OpenStruct.new(envelope: "")
end


Then('mock UpdateDocumentFolderPathJob job') do
  UpdateDocumentFolderPathJob.perform_now(@investor_kyc.class.name, @investor_kyc.id)
end

Then('Folder path should be present and correct') do
  expect(@investor_kyc.document_folder.full_path).to(eq(@investor_kyc.folder_path))
end

Then('the esign log is present') do
  @doc = Document.where(owner_tag:"Generated").last
  expect(@doc.esign_log.present?).to(eq(true))
end

Given('the investor has investor notice entry') do
  @investor ||= Investor.last
  @notice = InvestorNotice.create!(entity_id: @entity.id, owner: Deal.last, start_date:Date.today, end_date: Date.today + 1.month, active: true, title: "Test 1")
  @notice_entry = InvestorNoticeEntry.create!(investor_id: @investor.id, investor_notice_id: @notice.id,
                                         investor_entity_id: @investor.investor_entity_id,
                                         entity_id: @investor.entity_id, active: true)
end

Given('I update the investors investor entity id') do
  @investor.update(investor_entity_id: Entity.last.id)
end

Then('investor entity id should be updated in expected objects') do
  @investor.reload
  expect(@deal_investor.reload.investor_entity_id).to(eq(@investor.investor_entity_id))
  expect(@notice_entry.reload.investor_entity_id).to(eq(@investor.investor_entity_id))
  expect(InvestorAccess.last.investor_entity_id).to(eq(@investor.investor_entity_id))
end


Given('the entity_setting has {string}') do |args|
  key_values(@entity.entity_setting, args)
  @entity.entity_setting.save!
end

Given('there is an incoming email sent for this investor {string}') do |args|

  @incoming_email = FactoryBot.build(:incoming_email)
  key_values(@incoming_email, args)

  RAILS_APP_URL = "http://localhost:3000/incoming_emails/sendgrid"

  # Construct the request payload
  email_payload = {
    "text" => @incoming_email.body,
    "html" => @incoming_email.body,
    "sender_ip" => "209.85.218.49",
    "headers" => "Content-Type: multipart/alternative; boundary=\"000000000000015679062ad824de\"\nDKIM-Signature: v=1; ...", # Truncated for brevity
    "SPF" => "pass",
    "envelope" => { "to" => [@incoming_email.to], "from" => @incoming_email.from }.to_json,
    "attachments" => "0",
    "to" => @incoming_email.to,
    "subject" => @incoming_email.subject,
    "spam_score" => "-0.1",
    "spam_report" => "Spam detection software has NOT identified this email as spam.",
    "charsets" => { "to" => "UTF-8", "from" => "UTF-8", "subject" => "UTF-8", "text" => "utf-8", "html" => "utf-8" }.to_json,
    "dkim" => { "@gmail.com" => "pass" }.to_json,
    "from" => @incoming_email.from
  }

  # Convert payload to JSON
  json_payload = email_payload.to_json

  # Create URI object
  uri = URI.parse(RAILS_APP_URL)

  # Send HTTP POST request
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
  request.body = json_payload

  # Execute request and print response
  response = http.request(request)
  response.code.should == "200"
end

When('then the email should be {string} to the investor') do |added|

  IncomingEmail.count.should == 1
  last_incoming_email = IncomingEmail.last
  if added == "true"
    last_incoming_email.owner.should == Investor.find(1)
  else
    last_incoming_email.owner.should == nil
  end
  last_incoming_email.to.should == @incoming_email.to
  last_incoming_email.from.should == @incoming_email.from
  last_incoming_email.subject.should == @incoming_email.subject
  last_incoming_email.body.should == @incoming_email.body
end

When('I go to the Investor Kycs index page') do
  visit(investor_kycs_path)
end

When('I filter the investors with {string}') do |string|
  @investor_kyc = InvestorKyc.find_by(full_name: string)
  InvestorKycIndex.import!
  sleep(1)
  fill_in("search_input", with: string)
  sleep(0.5)
  # press enter key
  find("#search_input").send_keys(:return)

end

Then('I should see the filtered investors with {string}') do |string|
  expect(page).to have_content(string)
  expect(page).to have_content(@investor_kyc.investor_name)
  expect(page).to have_content(@investor_kyc.kyc_type.titleize)
  expect(page).not_to have_content("Investor 2")
  expect(page).not_to have_content("Investor 3")
  expect(page).not_to have_content("Investor 4")
end
