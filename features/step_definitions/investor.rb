Given('I am at the investor page') do
  visit("/investors")
end

When('I create a new investor {string}') do |arg1|
  @investor_entity = FactoryBot.build(:entity, entity_type: "Investor")
  key_values(@investor_entity, arg1)
  click_on("New Stakeholder")

  if (Entity.vcs.count > 0)
    fill_in('investor_investor_name', with: @investor_entity.name)
    find('ui-menu-item-wrapper', text: @investor_entity.name).click
  end
  fill_in('investor_investor_name', with: @investor_entity.name)
  fill_in('investor_pan', with: @investor_entity.pan)
  select("Founder", from: "investor_category")

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
  expect(page).to have_content(@investor.entity.name)
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

When('I create a new investor {string} for the existing investor entity') do |string|
  click_on("New Stakeholder")

  fill_in('investor_investor_name', with: @investor_entity.name)

  find('.ui-menu-item-wrapper', text: @investor_entity.name).click
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

Given('Given I upload an investor kyc file for employees') do
  # Sidekiq.redis(&:flushdb)

  visit(investor_kycs_path)
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
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investors.xlsx'), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(1)
  ImportUploadJob.perform_now(ImportUpload.last.id)
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

  end

end


Given('Given I upload an investors file for the fund') do
  visit(investors_path)
  click_on("Actions")
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/fund_investors.xlsx'), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(3)
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
    puts "Checking import of #{cc.full_name}"
    cc.full_name.should == user_data["Full Name"]
    cc.address.should == user_data["Address"]
    cc.PAN.should == user_data["PAN"]
    cc.bank_account_number.should == user_data["Bank Account"].to_s
    cc.ifsc_code.should == user_data["IFSC Code"].to_s

  end
end

Then('Aml Report should be generated for each investor kyc') do
  investor_kycs = @entity.investor_kycs
  investor_kycs.each do |kyc|
    kyc.aml_reports.count.should_not == 0
    kyc.aml_reports.each do |report|
      report.name.should == kyc.full_name
    end
  end
end

Given('Given Entity has ckyc_kra_enabled set to true') do
  @entity.update(enable_kycs: true)
  @user.permissions.set(:enable_kycs)
  @user.save!
  @user.reload
  @entity.entity_setting.update(ckyc_kra_enabled: true, fi_code: "123456", aml_enabled: true)
  @investor = FactoryBot.create(:investor, entity: @entity, investor_entity: Entity.first)
end

Given('I create a new InvestorKyc with pan {string}') do |string|
  visit(investor_kycs_path)
  sleep(2)
  click_on("New Investor Kyc")
  sleep(2)
  fill_in('investor_kyc_PAN', with: "PANNUMBER1")
  click_on("Next")
  sleep(3)
end

Given('I create a new InvestorKyc') do ||
  @investor_kyc = FactoryBot.create(:investor_kyc, entity: @entity)
  puts "\n########### KYC ############"
  puts @investor_kyc.to_json


  visit(investor_kycs_path)
  click_on("New Investor Kyc")  
  select(@investor_kyc.investor.investor_name, from: "investor_kyc_investor_id")
  fill_in('investor_kyc_full_name', with: @investor_kyc.full_name)
  select(@investor_kyc.residency.titleize, from: "investor_kyc_residency")
  fill_in('investor_kyc_PAN', with: @investor_kyc.PAN)
  fill_in('investor_kyc_birth_date', with: @investor_kyc.birth_date)
  
  click_on("Next")
  sleep(1)
  fill_in('investor_kyc_address', with: @investor_kyc.address)
  fill_in('investor_kyc_corr_address', with: @investor_kyc.corr_address)
  fill_in('investor_kyc_bank_account_number', with: @investor_kyc.bank_account_number)
  fill_in('investor_kyc_ifsc_code', with: @investor_kyc.ifsc_code)
  click_on("Next")
  sleep(1)
  
  fill_in('investor_kyc_expiry_date', with: @investor_kyc.expiry_date)
  fill_in('investor_kyc_comments', with: @investor_kyc.comments)
  click_on("Save")
  sleep(1)
  
end

Then('I should see ckyc and kra data comparison page') do
  expect(page).to have_content("CKYC")
  expect(page).to have_content("KRA")

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
  expect(page).to have_content("Investor kyc was successfully updated")
end



Then('I should be on the new documents page') do
  sleep(1)
  click_on("Ok")
  expect(current_path).to eq(new_document_path())
end

Then('when I upload the document for the kyc') do
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