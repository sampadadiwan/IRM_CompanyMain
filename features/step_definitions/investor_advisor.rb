  Given('given there are investor advisors {string}') do |emails|
    @investor_advisor_entity = FactoryBot.create(:entity, entity_type: "Investor Advisor")
    # puts @investor_advisor_entity.to_json

    emails.split(",").each do |email|
        u = FactoryBot.create(:user, email:, entity: @investor_advisor_entity)
        u.has_cached_role?(:investor_advisor).should ==  true
    end
  end

  Given('Given I upload {string} file for Investoment Advisors') do |file|
    @import_file = file
    visit(fund_path(@fund))
    click_on("Import")
    click_on("Import Investor Advisors")
    sleep(2)
    fill_in('import_upload_name', with: "Test Upload")
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
    sleep(2)
    click_on("Save")
    sleep(3)
    ImportUploadJob.perform_now(ImportUpload.last.id)
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
