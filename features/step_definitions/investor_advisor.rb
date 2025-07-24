  Given('given there are investor advisors {string}') do |emails|
    @investor_advisor_entity = FactoryBot.create(:entity, entity_type: "Investor Advisor")
    # puts @investor_advisor_entity.to_json

    emails.split(",").each do |email|
        u = FactoryBot.create(:user, email:, entity: @investor_advisor_entity)
        u.has_cached_role?(:investor_advisor).should ==  true
    end
  end

  Given('Given I upload {string} file for Investment Advisors') do |file|
    @import_file = file
    visit(fund_path(@fund))
    click_on("Import")
    click_on("Import Investor Advisors")
    #sleep(2)
    fill_in('import_upload_name', with: "Test Upload")
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
    sleep(2)
    click_on("Save")
    # sleep(3)
    expect(page).to have_content("Import Upload:")
    ImportUploadJob.perform_now(ImportUpload.last.id)
    ap InvestorAdvisor.all
  end

  Then('the investor advisors should be added to each investor') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    data.each_with_index do |row, idx|
        next if idx.zero? # skip header row
        user_data = [headers, row].transpose.to_h
        user = User.find_by_email(user_data["Email"].strip)
        investor = @entity.investors.where(investor_name: user_data["Investor"].strip).first
        # Check if user is added as an investor_advisor
        puts "Checking investor_advisor #{user.email} for #{investor.investor_entity.name}"
        investor.investor_entity.investor_advisors.where(user_id: user.id, entity_id: investor.investor_entity_id).count.should > 0
        # Check if he has permission to the Fund
        puts "Checking access_rights for investor_advisor #{user.email} for #{@fund.name}"
        fund = @entity.funds.where(name: user_data["Name"].strip).first
        fund.access_rights.where(user_id: user.id, entity_id: investor.investor_entity_id).count.should > 0
        # Check if he has been give investor access
        puts "Checking investor_access for #{user.email} in #{@entity.name}\n\n"
        @entity.investor_accesses.where(email: user.email).first.should_not be_nil
    end
  end


  
  Then('I switch to becoming the advisor for {string}') do |investor_name|
    #sleep(2)
    # Select the investor_name from the drop down with id investor_advisor
    within("#investor_advisors_form") do
      select(investor_name, from: "id")
    end
  end
  

Given('I go to Add Investor Advisor page for commmitment') do
  @capital_commitment ||= CapitalCommitment.first
  visit(capital_commitment_path(@capital_commitment))
  # click_on("Actions")
  click_on("Actions", match: :first)
# first(:button, 'Actions').click
# first(:link, 'Actions').click

  click_on("Add Investor Advisor")
end

Given('I fill IA form with details of a user that exists with role {string}') do |role|
  email = Faker::Internet.email
  entity_result = CreateInvestorAdvisorEntity.call(name: Faker::Company.name, primary_email: email)
  expect(entity_result.success?).to be true
  @entity = entity_result[:entity]
  user_result = FetchOrCreateUser.call(
      email: email,
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      entity_id: @entity.id,
      role: role.strip.to_sym
    )
  expect(user_result.success?).to be true
  @user = user_result[:user]
  @user.roles.destroy_all
  @user.add_role(role.strip.to_sym)
  @user.reload
  expect(@user.has_cached_role?(role.strip.to_sym)).to be true
  fill_in('investor_advisor_email', with: @user.email)
  p "Filling IA form with details of a user with role: #{role.strip} and email: #{@user.email}"
  click_on("Save")
end

Then('Investor Advisor is successfully created') do
  expect(page).to have_content("Investor advisor was successfully created.")
end

Given('I fill IA form with details of a user that is already an Investor Advisor for this fund') do
  @investor_advisor ||= InvestorAdvisor.last
  p "Filling IA form with details of an existing Investor Advisor: #{@investor_advisor.email}"
  fill_in('investor_advisor_email', with: @investor_advisor.email)
  click_on("Save")
end

Then('Investor Advisor creation fails with error {string}') do |string|
  p "Checking Error Message: #{string}"
  expect(page).to have_content(string)
end

Given('I fill IA form with details of a user that does not exist with details {string}') do |params|
  fill_in('investor_advisor_email', with: Faker::Internet.email)
  # advisor_entity_name,first_name,last_name
  if params.include?("advisor_entity_name")
    fill_in('investor_advisor_advisor_entity_name', with: Faker::Company.name)
  end
  if params.include?("first_name")
    fill_in('investor_advisor_first_name', with: Faker::Name.first_name)
  end
  if params.include?("last_name")
    fill_in('investor_advisor_last_name', with: Faker::Name.last_name)
  end
  p "Creating Investor Advisor with params: #{params}"
  click_on("Save")
end
