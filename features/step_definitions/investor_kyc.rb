  Given('I initiate creating InvestorKyc {string}') do |args|
    @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity)
    key_values(@investor_kyc, args)
    puts "\n########### KYC ############"
    puts @investor_kyc.to_json

    visit(investor_kycs_path)
    click_on("New KYC")
    click_on("Individual")
    sleep(2)
  end

  Then('I should see the kyc sebi fields') do
    expect(page).to have_content "Investor Category"
    expect(page).to have_content "Investor Sub Category"

    class_name = "individual"
    find('.select2-container', visible: true).click
    find('li.select2-results__option', text: @investor_kyc.investor.investor_name).click

    fill_in("#{class_name}_kyc_full_name", with: @investor_kyc.full_name)
    fill_in("#{class_name}_kyc_PAN", with: @investor_kyc.PAN)
    fill_in("#{class_name}_kyc_birth_date", with: @investor_kyc.birth_date)

    sub_category_dropdown = find("##{class_name}_kyc_properties_investor_sub_category")
    InvestorKyc::SEBI_INVESTOR_CATEGORIES.each do |category|
      category = category.to_s
      select(category.titleize, from: "#{class_name}_kyc_properties_investor_category")

      InvestorKyc::SEBI_INVESTOR_SUB_CATEGORIES_MAPPING.stringify_keys[category].each do |subcat|
        expect(sub_category_dropdown).to have_selector('option', text: subcat)
      end
    end

    click_on("Next")
    sleep(1)

    fill_in("#{class_name}_kyc_address", with: @investor_kyc.address)
    fill_in("#{class_name}_kyc_corr_address", with: @investor_kyc.corr_address)
    fill_in("#{class_name}_kyc_bank_name", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_bank_branch", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_bank_account_number", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_ifsc_code", with: @investor_kyc.ifsc_code)

    click_on("Next")
    sleep(1)

    click_on("Save")
    sleep(1)

  end

  Then('I should see the sebi fields on investor kyc show page') do
    visit(investor_kyc_path(InvestorKyc.last))
    expect(page).to have_content "Investor Category"
    expect(page).to have_content "Investor Sub Category"
  end

  Then('I should not see the kyc sebi fields') do

    expect(page).not_to have_content "Investor Category"
    expect(page).not_to have_content "Investor Sub Category"

    class_name = "individual"
    find('.select2-container', visible: true).click
    find('li.select2-results__option', text: @investor_kyc.investor.investor_name).click

    fill_in("#{class_name}_kyc_full_name", with: @investor_kyc.full_name)
    fill_in("#{class_name}_kyc_PAN", with: @investor_kyc.PAN)
    fill_in("#{class_name}_kyc_birth_date", with: @investor_kyc.birth_date)

    click_on("Next")
    sleep(1)

    fill_in("#{class_name}_kyc_address", with: @investor_kyc.address)
    fill_in("#{class_name}_kyc_corr_address", with: @investor_kyc.corr_address)
    fill_in("#{class_name}_kyc_bank_name", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_bank_branch", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_bank_account_number", with: @investor_kyc.bank_account_number)
    fill_in("#{class_name}_kyc_ifsc_code", with: @investor_kyc.ifsc_code)
    click_on("Next")
    sleep(1)

    click_on("Save")
    sleep(1)
  end

  Then('I should not see the sebi fields on investor kyc show page') do
    visit(investor_kyc_path(InvestorKyc.last))
    expect(page).not_to have_content "SEBI Investor Category"
    expect(page).not_to have_content "SEBI Investor Sub Category"
  end

  Then('The admin adds sebi fields') do
    visit(entity_path(@entity))
    click_on("Add SEBI Fields")
    sleep(1)
    expect(page).to have_content "SEBI Fields"
    expect(page).not_to have_content "Add SEBI Fields"
  end

  Then('Sebi fields must be added') do
    ["IndividualKyc", "NonIndividualKyc", "InvestmentInstrument"].each do |class_name|
      form_type = FormType.where(name: class_name, entity_id: @entity.id).first
      class_name.constantize::SEBI_REPORTING_FIELDS.stringify_keys.keys.each do |cf|
        form_type.form_custom_fields.pluck(:name).include?(cf).should be_truthy
      end
    end
  end

  Given('I remove the sebi fields') do
    result = RemoveSebiFields.wtf?(entity: @entity)
    expect(result.success?).to be_truthy
  end

  Then('Sebi fields must be removed') do
    ["IndividualKyc", "NonIndividualKyc", "InvestmentInstrument"].each do |class_name|
      form_type = FormType.where(name: class_name, entity_id: @entity.id).first
      class_name.constantize::SEBI_REPORTING_FIELDS.stringify_keys.keys.each do |cf|
        form_type.form_custom_fields.pluck(:name).include?(cf).should be_falsey
      end
    end
  end


Given('Given I upload an investor kyc file for the fund') do
  visit(investor_kycs_path)
  click_on("Upload/Download")
  click_on("Upload KYC Details")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/investor_kycs.xlsx"), make_visible: true)
  #sleep((2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(4)
  ImportUpload.last.failed_row_count.should == 0
end

Then('the investor kycs must have the data in the sheet') do
  file = File.open("./public/sample_uploads/investor_kycs.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

investor_kycs = @entity.investor_kycs.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row


    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    kyc = investor_kycs[idx-1]
    puts "Checking import of #{kyc.investor.investor_name}"
    kyc.investor.investor_name.should == user_data["Investor"].strip
    kyc.full_name.should == user_data["Investing Entity"]&.strip
    kyc.PAN.should == user_data["Pan"]&.strip
    kyc.address.should == user_data["Address"].strip
    kyc.corr_address.should == user_data["Correspondence Address"]&.strip
    InvestorKyc.kyc_types[kyc.kyc_type].should == user_data["Kyc Type"].strip
    kyc.custom_fields["residency"].should == user_data["Residency"]&.strip
    kyc.birth_date.to_date.should == user_data["Date Of Birth"].to_date
    kyc.bank_name.should == user_data["Bank Name"].strip
    kyc.bank_account_number.should == user_data["Bank Account Number"].to_s.strip
    kyc.bank_account_type.should == user_data["Account Type"].strip
    kyc.ifsc_code.should == user_data["Ifsc Code"].strip
    kyc.verified.should == (user_data["Verified"]&.strip&.downcase == "yes" || user_data["Verified"]&.strip&.downcase == "true")

    if user_data["Form Tag"].present?
      form_type = @entity.form_types.where(name: kyc.type, tag: user_data["Form Tag"].strip).last
      puts "Checking form type for #{kyc.investor.investor_name} with tag #{user_data["Form Tag"].strip} #{form_type&.name}"
      puts "FCF: " + form_type.form_custom_fields.pluck(:name).to_s if form_type
      kyc.form_type.should == form_type
    else
      form_type = @entity.form_types.where(name: kyc.type).last
      puts "Checking form type for #{kyc.investor.investor_name} with no tag #{form_type&.name}"
      puts "FCF: " + form_type.form_custom_fields.pluck(:name).to_s if form_type
      kyc.form_type.should == form_type
    end
  end
end

Given('there is a FormType {string} with custom fields {string}') do |form_type_args, custom_field_names|
  form_type = FormType.new
  key_values(form_type, form_type_args)
  form_type.entity = @entity
  form_type.save!
  puts "\n########### FormType ############"
  puts form_type.to_json
  custom_field_names.split(',').each do |name|
    form_type.form_custom_fields.create!(name: name.strip, field_type: "TextField", required: false)
  end
end

Then('there are {string} records for the form type {string}') do |count, name|
  FormType.where(name: name, entity_id: @entity.id).count.should == count.to_i
end


