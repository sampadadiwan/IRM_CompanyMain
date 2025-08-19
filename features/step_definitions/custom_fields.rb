
Given('I go to add a new custom form') do
  visit(new_form_type_path(debug: true))
  # click_link("New Form Type")
end

Given('I add a custom form for {string} with reg env {string} and tag {string}') do |class_name, reg_env, tag|
  select(class_name, from: "form_type_name")
  fill_in("form_type_tag", with: tag)
  fill_in("form_type_reg_env", with: reg_env)
  click_on("Save")
  sleep(2)
  @form_type = FormType.last
end

Then('{string} regulatory fields are added to the {string} form') do |reg_env, class_name|
  @form_type ||= FormType.where(name: class_name).last
  if reg_env.present?
    # Check if the regulatory fields are present
    expect(@form_type.form_custom_fields.where(reg_env: reg_env).count).to be > 0
  else
    # Check if no regulatory fields are present
    expect(@form_type.form_custom_fields.where.not(reg_env: nil).count).to eq(0)
  end
end

Given('I add a new {string} KYC with custom form tag {string}') do |type, tag|
  click_on("New KYC")
  type = type.gsub("Kyc", "")
  puts "Adding new #{type} KYC with tag #{tag}"
  puts "Entity form types #{@entity.form_types.pluck(:name, :tag).inspect}"
  if tag.present? && @entity.form_types.where(name:"IndividualKyc").count > 1
    # all("#{type} (#{tag})").first.click
    click_on("#{type} (#{tag})")
    # Clicks the second link/button
    # puts all(:link_or_button, "#{type} (#{tag})")[1]
    # all(:link_or_button, "#{type} (#{tag})")[1].click
  else
    # all("#{type}").first.click
    all(:link_or_button, "#{type}")[2].click
    # click_on("#{type}")
  end
end

Given('I fill InvestorKyc details with regulatory fields {string} with files {string} for {string}') do |args, files, kyc_url_params|
  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity)
  files = files.downcase
  key_values(@investor_kyc, args)

  puts "\n########### KYC ############"
  puts @investor_kyc.to_json

  # class_name = @investor_kyc.type_from_kyc_type.underscore
  class_name = "individual_kyc"

  if !current_path.include?("edit")
    select(@investor_kyc.investor.investor_name, from: "#{class_name}_investor_id")
  end

  if files.include?("pan")
    page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
      within '#custom_file_upload_pan_tax_id' do
        click_on 'Choose file'
      end
    end
  end
  sleep(4)

  fill_in("#{class_name}_full_name", with: @investor_kyc.full_name)
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

  sleep(2)
  fill_in("#{class_name}_address", with: @investor_kyc.address)
  fill_in("#{class_name}_corr_address", with: @investor_kyc.corr_address)
  fill_in("#{class_name}_bank_name", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_branch", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_bank_account_number", with: @investor_kyc.bank_account_number)
  fill_in("#{class_name}_ifsc_code", with: @investor_kyc.ifsc_code)
  click_on("Next")
  #sleep(1)

  # go to regulatory custom fields page
  if args.include?("properties")
    click_on("Next")
    @investor_kyc.properties.each do |key, value|
      name = FormCustomField.to_name(key)
      select(value, from: "#{class_name}_properties_#{name}")
    end
  end
  #sleep(1)
  click_on("Save")

  expect(page).to have_content("successfully")

end

Given('I go to KYCs page') do
  visit(investor_kycs_path)
end

Given('I edit the {string} kyc') do |position|
  @kyc = if position == "first"
           InvestorKyc.first
         else
           InvestorKyc.last
         end
  visit(edit_investor_kyc_path(@kyc))
end

Given('I fill in all details and regulatory custom fields are not present in the form') do
  # three steps
end

Given('I go to PortfolioCompany show page') do
  @portfolio_company ||= PortfolioCompany.first
  visit(investor_path(@portfolio_company))
end

Given('I go to the Instruments tab') do
  click_on"Instruments"
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  sleep(1)
end

Given('I add a new Instrument with custom form tag {string}') do |tag|
  click_on("New")
  if tag.present? && @portfolio_company.entity.form_types.where(name:"InvestmentInstrument").count > 1
  click_on("Investment Instrument (#{tag})")
  else
    click_on("Investment Instrument")
  end
end

Given('I fill the instrument form with the regulatory fields') do
  fill_in("investment_instrument_name", with: "Test Instrument")
  select("INR", from: "investment_instrument_currency")
  fill_in("investment_instrument_investment_domicile", with: "Domestic")
  select("Mutual Fund (MF)", from: "investment_instrument_properties_sebi_type_of_investee_company")
  select("Unlisted Equity/Equity Linked", from: "investment_instrument_properties_sebi_type_of_security")
  fill_in("investment_instrument_properties_sebi_details_of_security", with: "Test Security Details")
  fill_in("investment_instrument_properties_sebi_isin", with: "INE123456789")
  fill_in("investment_instrument_properties_sebi_registration_number", with: "SEBI123456")
  select("Yes", from: "investment_instrument_properties_sebi_is_associate")
  select("Yes", from: "investment_instrument_properties_sebi_is_managed_or_sponsored_by_aif")
  select("Biotechnology", from: "investment_instrument_properties_sebi_sector")
  select("Yes", from: "investment_instrument_properties_sebi_offshore_investment")
  click_on("Save")
  @instrument = InvestmentInstrument.last
end

Then('I should see the Instrument details on the details page and regulatory fields {string}') do |fields_present|
  @instrument = InvestmentInstrument.last
  visit(investment_instrument_path(@instrument))
  expect(page).to have_content("Test Instrument")
  expect(page).to have_content("INR")
  expect(page).to have_content("Domestic")
  if fields_present == "present"
    expect(page).to have_css('a.show_details_link[href=".show_reporting_fields_SEBI"]', visible: true)
    find('a.show_details_link[href=".show_reporting_fields_SEBI"]', visible: true).click

    expect(page).to have_content("Sebi Reporting Fields")
    expect(page).to have_content("Type of Investee Company")
    expect(page).to have_content("Type of Security")
    expect(page).to have_content("Details of Security (if Type of Security chosen is Others)")
    expect(page).to have_content("ISIN")
    expect(page).to have_content("SEBI Registration Number")
    expect(page).to have_content("Is Associate")
    expect(page).to have_content("Is Managed or Sponsored by AIF")
    expect(page).to have_content("Sector")
    expect(page).to have_content("Offshore Investment")

    expect(page).to have_content("Mutual Fund (MF)")
    expect(page).to have_content("Unlisted Equity/Equity Linked")
    expect(page).to have_content("Test Security Details")
    expect(page).to have_content("INE123456789")
    expect(page).to have_content("SEBI123456")
    expect(page).to have_content("Yes")
    expect(page).to have_content("Biotechnology")
  else
    expect(page).not_to have_css('a.show_details_link[href=".show_reporting_fields_SEBI"]')
    expect(page).not_to have_content("Sebi Reporting Fields")
    expect(page).not_to have_content("Type of Investee Company")
    expect(page).not_to have_content("Type of Security")
    expect(page).not_to have_content("Details of Security (if Type of Security chosen is Others)")
    expect(page).not_to have_content("ISIN")
    expect(page).not_to have_content("SEBI Registration Number")
    expect(page).not_to have_content("Is Associate")
    expect(page).not_to have_content("Is Managed Or Sponsored by AIF")
    expect(page).not_to have_content("Sector")
    expect(page).not_to have_content("Offshore Investment")
  end
end

Then('I should see the investor kyc details on the details page and regulatory fields {string}') do |string|
  @kyc = InvestorKyc.last
  visit(investor_kyc_path(@kyc))
  expect(page).to have_content(@kyc.full_name)
  expect(page).to have_content(@kyc.PAN)
  expect(page).to have_content(@kyc.birth_date.strftime("%d %B, %Y"))
  expect(page).to have_content(@kyc.address)
  expect(page).to have_content(@kyc.corr_address)
  expect(page).to have_content(@kyc.bank_account_number)
  expect(page).to have_content(@kyc.ifsc_code)
  if string == "present"
    expect(page).to have_css('a.show_details_link[href=".show_reporting_fields_SEBI"]', visible: true)
    find('a.show_details_link[href=".show_reporting_fields_SEBI"]', visible: true).click

    expect(page).to have_content("Sebi Reporting Fields")
    expect(page).to have_content("Investor Category")
    expect(page).to have_content("Investor Sub Category")
    expect(page).to have_content(@kyc.json_fields["sebi_investor_category"])
    expect(page).to have_content(@kyc.json_fields["sebi_investor_sub_category"])
  else
    expect(page).not_to have_css('a.show_details_link[href=".show_reporting_fields_SEBI"]')
    expect(page).not_to have_content("Sebi Reporting Fields")
    expect(page).not_to have_content("Investor Category")
    expect(page).not_to have_content("Investor Sub Category")
  end
end


Given('I fill the instrument form without the regulatory fields') do
  fill_in("investment_instrument_name", with: "Test Instrument 2")
  select("INR", from: "investment_instrument_currency")
  fill_in("investment_instrument_investment_domicile", with: "Domestic")
  click_on("Save")
  sleep(2)
  @instrument = InvestmentInstrument.last
end



Then('{string} regulatory fields are not added to the {string} form') do |reg_env, class_name|
  @form_type ||= FormType.where(name: class_name).last
  @form_type.form_custom_fields.where(reg_env: reg_env).count.should == 0
end

Given('I go and edit the {string} custom form with tag {string} and url param {string}') do |class_name, tag, url_param|
  temp_path = edit_form_type_path(@form_type)
  if url_param.present?
    temp_path += "?#{url_param}"
  end
  visit temp_path
end

Given('I fill in the reg env with {string} and save') do |reg_env|
  fill_in("form_type_reg_env", with: reg_env)
  click_on("Save")
  sleep(2)
  @form_type.reload
end

Given('I am using the last instrument created with the custom form tag {string}') do |tag|
  temp_form_type = FormType.where(name: "InvestmentInstrument", tag: tag).last
  expect(temp_form_type).not_to be_nil, "Form Type with name InvestmentInstrument and tag #{tag} not found"
  expect(@form_type).to eq(temp_form_type), "Expected form type to be #{temp_form_type.name} but was #{@form_type.name}"
  @instrument = InvestmentInstrument.where(form_type_id: @form_type.id).last
end

Given('I go to see the Instrument details on the details page') do
  visit(investment_instrument_path(@instrument))
  expect(page).to have_content(@instrument.name)
end

Given('I go to edit the instrument created with the custom form tag {string}') do |tag|
  temp_form_type = FormType.where(name: "InvestmentInstrument", tag: tag).last
  expect(temp_form_type).not_to be_nil, "Form Type with name InvestmentInstrument and tag #{tag} not found"
  expect(@form_type).to eq(temp_form_type), "Expected form type to be #{temp_form_type.name} but was #{@form_type.name}"

  @instrument = InvestmentInstrument.where(form_type_id: @form_type.id).last
  visit(edit_investment_instrument_path(@instrument))
end

Given('I edit the instrument form with the regulatory fields') do
  fill_in("investment_instrument_name", with: "Test Instrument")
  fill_in("investment_instrument_investment_domicile", with: "Domestic")
  select("Mutual Fund (MF)", from: "investment_instrument_properties_sebi_type_of_investee_company")
  select("Unlisted Equity/Equity Linked", from: "investment_instrument_properties_sebi_type_of_security")
  fill_in("investment_instrument_properties_sebi_details_of_security", with: "Test Security Details")
  fill_in("investment_instrument_properties_sebi_isin", with: "INE123456789")
  fill_in("investment_instrument_properties_sebi_registration_number", with: "SEBI123456")
  select("Yes", from: "investment_instrument_properties_sebi_is_associate")
  select("Yes", from: "investment_instrument_properties_sebi_is_managed_or_sponsored_by_aif")
  select("Biotechnology", from: "investment_instrument_properties_sebi_sector")
  select("Yes", from: "investment_instrument_properties_sebi_offshore_investment")
  click_on("Save")
  @instrument = InvestmentInstrument.last
end

Given('I add a custom form for {string} with tag {string}') do |class_name, tag|
  select(class_name, from: "form_type_name")
  fill_in("form_type_tag", with: tag)
  click_on("Save")
  sleep(2)
  @form_type = FormType.last
end

Given('I go the the form types index page') do
  visit(form_types_path)
end

Given('I click add {string} reporting fields to {string} form from the dropdown') do |reg_env, form_name|
  @form_type ||= FormType.where(name: form_name).last

  click_on("Add Reporting Fields")
  within(".dropdown-menu") do
    click_on(reg_env)
  end
  click_on("Proceed")
  sleep(1)
  expect(page).to have_content("Reporting fields added successfully to #{@form_type.name} #{@form_type.tag.presence || @form_type.id}")
end

Given('I verify the KYC') do
  click_on("Verify")
end

Given('I edit the reporting fields for the verified KYC') do
  expect(page).to have_content("Edit", wait: 5)
  click_on("Edit")
end

Given('I fill in the regulatory fields with {string}') do |properties|
  @kyc ||= InvestorKyc.last
  expect(page).to have_content("#{@kyc.to_s} Reporting Fields")
  properties.split(",").each do |property|
    field_key, value = property.split(":")
    field_key = field_key.strip
    value = value.strip
    puts "Filling in #{field_key} with value #{value}"
    field = "#{@kyc.type.underscore}_properties_#{field_key}"
    select(value, from: field)
  end
  click_on("Save")
  expect(page).to have_content("successfully")
  @kyc.reload
end

Given('I try to edit the reporting via URL') do
  visit(edit_reporting_fields_investor_kyc_path(@kyc))
end

Given('The Kyc is unverified') do
  @kyc.assign_attributes(verified: false)
  @kyc.save(validate: false)
  expect(@kyc.verified).to be_falsey
end
