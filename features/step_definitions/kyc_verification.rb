Given('I go to create InvestorKyc {string}') do |args|
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)

  @investor_kyc = FactoryBot.build(:investor_kyc, entity: @entity)
  key_values(@investor_kyc, args)
  puts "\n########### KYC ############"
  puts @investor_kyc.to_json

  visit(investor_kycs_path)
  click_on("New KYC")
  click_on("Individual")
  sleep(2)

  class_name = "individual"
  find('.select2-container', visible: true).click
  find('li.select2-results__option', text: @investor_kyc.investor.investor_name).click


  fill_in("#{class_name}_kyc_full_name", with: @investor_kyc.full_name)
  fill_in("#{class_name}_kyc_PAN", with: @investor_kyc.PAN)
  page.attach_file('./public/sample_uploads/example_pan.jpeg') do
    within '#custom_file_upload_pan_tax_id' do
      click_on 'Choose file'
    end
  end
  sleep(2)
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
  sleep(5)
  @og_pan_verification_response = {}
  @og_bank_verification_response = {}
end

Given('Entity PAN verification is enabled') do
  @ent1 = Entity.last
  @ent1.entity_setting.pan_verification = true
  @ent1.entity_setting.save
  @entity.entity_setting.pan_verification = true
  @entity.entity_setting.save
end

Then('Kyc Pan Verification is triggered') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  @kyc = InvestorKyc.last
  sleep(5)
  @kyc.reload
  @kyc.pan_verification_response.should_not == @og_pan_verification_response
end

Then('when the Kyc name is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)

  @kyc = InvestorKyc.last
  @og_pan_verification_response = @kyc.pan_verification_response
  @og_bank_verification_response = @kyc.bank_verification_response
  visit(edit_investor_kyc_path(@kyc))

  class_name = "individual"


  fill_in("#{class_name}_kyc_full_name", with: @investor_kyc.full_name + " Updated")

  click_on("Next")
  sleep(1)

  click_on("Next")
  sleep(1)

  click_on("Save")
  sleep(1)
end

Then('when the Kyc PAN is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  @kyc = InvestorKyc.last
  @og_pan_verification_response = @kyc.pan_verification_response
  visit(edit_investor_kyc_path(@kyc))

  class_name = "individual"
  fill_in("#{class_name}_kyc_PAN", with: @investor_kyc.PAN+"A")

  click_on("Next")
  sleep(1)

  click_on("Next")
  sleep(1)

  click_on("Save")
  sleep(1)
end

Given('Entity Bank verification is enabled') do
  @ent1 = Entity.last
  @ent1.entity_setting.bank_verification = true
  @ent1.entity_setting.save
  @entity.entity_setting.bank_verification = true
  @entity.entity_setting.save
end

Then('Kyc Bank Verification is triggered') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @kyc = InvestorKyc.last
  sleep(5)
  @kyc.reload
  @kyc.bank_verification_response.should_not == @og_bank_verification_response
end

Then('when the Kyc Bank Account number is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @kyc = InvestorKyc.last
  @og_bank_verification_response = @kyc.bank_verification_response
  visit(edit_investor_kyc_path(@kyc))

  class_name = "individual"

  click_on("Next")
  sleep(1)

  fill_in("#{class_name}_kyc_bank_account_number", with: @investor_kyc.bank_account_number + "5")
  click_on("Next")
  sleep(1)

  click_on("Save")
  sleep(1)
end

Then('when the Kyc Bank IFSC is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @kyc = InvestorKyc.last
  @og_bank_verification_response = @kyc.bank_verification_response
  visit(edit_investor_kyc_path(@kyc))

  class_name = "individual"

  click_on("Next")
  sleep(1)

  fill_in("#{class_name}_kyc_ifsc_code", with: @investor_kyc.ifsc_code+"1")
  click_on("Next")
  sleep(1)

  click_on("Save")
  sleep(1)
end

def pan_response
  {:status=>"success",
  :fathers_name=> Faker::Name.unique.name,
  :name=> Faker::Name.unique.name,
  :dob=>"01/01/1990",
  :id_no=> Faker::Alphanumeric.alphanumeric(number: 10),
  :is_pan_dob_valid=>true,
  :name_matched=>true,
  :verified=>nil}
end

def bank_response
  body = {"id"=> Faker::Alphanumeric.alphanumeric(number: 16),
  "verified"=>"true",
  "verified_at"=> Time.now.strftime('%Y-%m-%d %H:%M:%S') ,
  "beneficiary_name_with_bank"=> Faker::Name.unique.name,
  "fuzzy_match_result"=>"true",
  "fuzzy_match_score"=>100}
  OpenStruct.new(verified: true, body: body.to_json)
end
