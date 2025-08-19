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
      binding.pry
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


