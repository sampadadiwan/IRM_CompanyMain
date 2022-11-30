Given('I am at the investor page') do
  visit("/investors")
end

When('I create a new investor {string}') do |arg1|
  @investor_entity = FactoryBot.build(:entity, entity_type: "VC")
  key_values(@investor_entity, arg1)
  click_on("New Investor")

  if (Entity.vcs.count > 0)
    fill_in('investor_investor_name', with: @investor_entity.name)
    find('ui-menu-item-wrapper', text: @investor_entity.name).click
  end
  fill_in('investor_investor_name', with: @investor_entity.name)
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
end


Given('there is an existing investor {string}') do |arg1|
  steps %(
        Given there is an existing investor entity "#{arg1}"
    )
  @investor = FactoryBot.create(:investor, investor_entity_id: @investor_entity.id, entity_id: @entity.id)
  puts "\n####Investor####\n"
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
  
    puts "\n####Investor USer####\n"
    puts @investor_user.to_json
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
  @investor_entity = FactoryBot.build(:entity, entity_type: "VC")
  key_values(@investor_entity, arg1)
  @investor_entity.save
  puts "\n####Investor Entity####\n"
  puts @investor_entity.to_json
  EntityIndex.import
end

When('I create a new investor {string} for the existing investor entity') do |string|
  click_on("New Investor")
  
  fill_in('investor_investor_name', with: @investor_entity.name)
  
  find('.ui-menu-item-wrapper', text: @investor_entity.name).click
  select("Founder", from: "investor_category")
  click_on("Save")
end


Given('Given I upload an investor access file for employees') do
  # Sidekiq.redis(&:flushdb)

  visit(investor_path(Investor.first))
  click_on("Employee Investors")
  click_on("Upload Employee Investors")
  fill_in('import_upload_name', with: "Test Investor Access Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(1)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('There should be {string} investor access created') do |count|
  InvestorAccess.count.should == count.to_i
end


Given('Given I upload an investors file for the startup') do
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
    inv.tag_list.join(", ").should == user_data["Tags"]
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
  sleep(2)
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