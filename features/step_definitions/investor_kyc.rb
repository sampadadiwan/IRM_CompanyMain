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
    select(@investor_kyc.residency.titleize, from: "#{class_name}_kyc_residency")
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
    select(@investor_kyc.residency.titleize, from: "#{class_name}_kyc_residency")
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
