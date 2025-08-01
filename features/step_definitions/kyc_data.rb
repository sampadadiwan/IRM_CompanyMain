Given('an entity with a fund and an investor exists') do
  
  steps %(
      Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
      Given the user has role "company_admin"
      Given there is an existing investor "name=Investor 1" with "1" users
    )
  @investor.investor_entity.permissions.set(:enable_kycs)
  @investor.investor_entity.save!
  @investor_user.add_role(:investor)
  # Stub CKYC/KRA API calls
  allow_any_instance_of(KycVerify).to receive(:search_ckyc).and_return(JSON.parse(sample_ckyc_search_response))
  allow_any_instance_of(KycVerify).to receive(:send_otp).and_return(JSON.parse(sample_send_otp_response))
  allow_any_instance_of(KycVerify).to receive(:download_ckyc_response).and_return(JSON.parse(sample_download_ckyc_response))
  allow_any_instance_of(KycVerify).to receive(:get_kra_pan_response).and_return(JSON.parse(sample_kra_response))
end

Given('CKYC is enabled for the entity with a valid FI code') do
  @entity.entity_setting.update(fi_code: 'FI123456')
  @entity.permissions.set(:enable_ckyc)
  @entity.save!
end

When('I navigate to the new individual KYC page') do
  visit(investor_path(@investor))
  click_on("KYC")
  click_on("New KYC")
  click_on("Individual")
end

When('I fill in {string} with {string}') do |field, data|
  field = field.strip  
  data = Time.zone.parse(data) if field.include?("date") && data.present?
  fill_in("individual_kyc_#{field}", with: data)
end

When('I fill in kyc data {string} with {string}') do |field, data|
  field = field.strip  
  data = Time.zone.parse(data) if field.include?("date") && data.present?
  fill_in("kyc_data_#{field}", with: data)
end

When('I click the {string} button') do |string|
  click_on(string)
end

Then('I should be on the OTP entry page') do
  expect(page).to have_content("OTP has been sent to the registered mobile number")
end

When('I enter a valid OTP') do
  fill_in("otp", with: "123456") # Assuming a valid OTP is "123456"
  click_on("Submit")
end

Then('I should be on the CKYC\/KRA assign page') do
  expect(page).to have_content("Source")
  expect(page).to have_content("Status")
  expect(page).to have_content("Correspondence Address")
  expect(page).to have_content("Permanent Address")
  expect(page).to have_content("Email")
end

Then('I should see the message {string}') do |string|
  expect(page).to have_content(string)
end

Then('the KYC form should be populated with the CKYC data') do
  @kyc_data ||= KycData.ckyc.last
  expect(find_field("individual_kyc_full_name").value).to eq(@kyc_data.full_name)
  expect(find_field("individual_kyc_PAN").value).to eq(@kyc_data.PAN)

  if @kyc_data.birth_date.present?
    expect(find_field("individual_kyc_birth_date").value).to eq(@kyc_data.birth_date.strftime("%Y-%m-%d"))
  end
  click_on("Next")
  expect(page).to have_content("Address")
  expect(find_field("individual_kyc_address").value).to eq(@kyc_data.perm_address)
  expect(find_field("individual_kyc_corr_address").value).to eq(@kyc_data.corr_address)
  click_on("Next")

end

Then('I fill in the form and it is populated with the CKYC data') do
  @kyc_data ||= KycData.ckyc.last
  expect(find_field("individual_kyc_full_name").value).to eq(@kyc_data.full_name)
  expect(find_field("individual_kyc_PAN").value).to eq(@kyc_data.PAN)
  page.attach_file('./public/sample_uploads/example_pan.jpeg') do
    within '#custom_file_upload_pan' do
      click_on 'Choose file'
    end
  end

  if @kyc_data.birth_date.present?
    expect(find_field("individual_kyc_birth_date").value).to eq(@kyc_data.birth_date.strftime("%Y-%m-%d"))
  end
  click_on("Next")

  expect(page).to have_content("Address")
  page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
    within '#custom_file_upload_address_proof' do
      click_on 'Choose file'
    end
  end

  # page.attach_file('./public/sample_uploads/Offer_1_SPA.pdf') do
  #   within '#custom_file_upload_cancelled_cheque_bank_statement' do
  #     click_on 'Choose file'
  #   end
  # end
  expect(find_field("individual_kyc_address").value).to eq(@kyc_data.perm_address)
  expect(find_field("individual_kyc_corr_address").value).to eq(@kyc_data.corr_address)
  select("Savings Account", from: "individual_kyc_bank_account_type")
  fill_in("individual_kyc_bank_name", with: Faker::Bank.name)
  fill_in("individual_kyc_bank_branch", with: Faker::Bank.name)
  fill_in("individual_kyc_bank_account_number", with: Faker::Alphanumeric.alphanumeric(number: 10))
  fill_in("individual_kyc_ifsc_code", with: Faker::Bank.swift_bic)
  click_on("Next")
end

And('I go to assign ckyc\/kra data') do
  @investor_kyc ||= InvestorKyc.last
  visit ("/kyc_datas/compare_ckyc_kra?investor_kyc_id=#{@investor_kyc.id}")
  expect(page).to have_content("CKYC")
end

When('I save the KYC form') do
  while(page.has_button?("Next") && !page.has_button?("Save"))
    click_on("Next")
  end

  click_on("Save")
end

Then('I should be on the KYC details page') do
  expect(page.current_url.include?("investor_kycs/")).to be true
end

Then('the page should display the correct KYC details') do
  %i[full_name PAN birth_date perm_address corr_address].each do |field|
    res = @kyc_data.send(field.to_s)
    res = res.strftime("%d %B, %Y") if field == :birth_date && res.present?
    expect(page).to have_content(res)
  end
end

Then('I should be on the KYC data edit page') do
  expect(page.current_url.include?("kyc_datas/")).to be true
  expect(page.current_url.include?("/edit")).to be true
  expect(page).to have_content("Investor kyc")
  expect(page).to have_content("Pan")
end

Then('I should be on the Investor KYC edit page') do
  expect(page).to have_content("Kyc type")
  expect(page.current_url.include?("investor_kycs/")).to be true
  expect(page.current_url.include?("/edit")).to be true
end

Then('the {string} field should be pre-filled with the valid PAN') do |string|
  @investor_kyc ||= InvestorKyc.last
  expect(find_field("individual_kyc_#{string}").value).to eq(@investor_kyc.PAN)
end

Given('KRA is enabled for the entity with a valid FI code') do
  @entity.entity_setting.update(fi_code: 'FI123456')
  @entity.permissions.set(:enable_kra)
  @entity.save!
end

Then('the KYC form should be populated with the KRA data') do
 @kyc_data = KycData.kra.last
  # expect individual_kyc_full_name to be pre-filled with thekyc_data.full_name
  expect(find_field("individual_kyc_full_name").value).to eq(@kyc_data.full_name)
  # expect individual_kyc_pan to be pre-filled with the kyc_data.PAN
  expect(find_field("individual_kyc_PAN").value).to eq(@kyc_data.PAN)

  if @kyc_data.birth_date.present?
    expect(find_field("individual_kyc_birth_date").value).to eq(@kyc_data.birth_date.strftime("%Y-%m-%d"))
  end
  click_on("Next")
  expect(find_field("individual_kyc_address").value).to eq(@kyc_data.perm_address)
  expect(find_field("individual_kyc_corr_address").value).to eq(@kyc_data.corr_address)
  click_on("Next")
end

Then('I should see both {string} and {string} data sections') do |string, string2|
  expect(page).to have_content(string)
  expect(page).to have_content(string2)
end

Then('I select {string} from the KYC actions menu') do |string|
  click_on("KYC Actions")
  click_on(string)
end

Then('the page should display the correct CKYC details') do
  @kyc_data ||= KycData.ckyc.last
  steps %(
    Then the page should display the correct KYC details
  )
end

Then('I should be on the KYC data show page') do
  expect(page.current_url.include?("kyc_datas/")).to be true
end

When('I navigate to the {string} tab for the investor kyc') do |string|
  @investor_kyc ||= InvestorKyc.last
  visit(investor_kyc_path(@investor_kyc))
  expect(page).to have_content("Kyc Type")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  click_on(string)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content(/new (ckyc|kra) data/i, wait: 10)
end

Given('CKYC and KRA are enabled for the entity with a valid FI code') do
  @entity.entity_setting.update(fi_code: 'FI123456')
  @entity.permissions.set(:enable_kra)
  @entity.permissions.set(:enable_ckyc)
  @entity.save!
end

Given('the investor has a verified user with KYC permissions') do
  @investor_user.extended_permissions.set(:investor_kyc_create) 
  @investor_user.extended_permissions.set(:investor_kyc_update) 
  @investor_user.extended_permissions.set(:investor_kyc_read)
  @investor_user.save! 
end

Given('I send a KYC request to the investor') do
  visit(investor_path(@investor))
  click_on("KYC")
  click_on("New KYC")
  expect(page).to have_text("Send KYC to Stakeholder")
  expect(page).to have_button("Send KYC to Stakeholder", wait: 5)
  # find("form.deleteButton button", text: "Send KYC to Stakeholder", visible: :all).click
  # accept_confirm do
    # find_button("Send KYC to Stakeholder", visible: :all).click
  # end
  # find_button("Send KYC to Stakeholder", visible: :all).click
  # 
  # button = find("form.deleteButton button", visible: :all)
  # page.execute_script("arguments[0].click()", button)

  button = find("form.deleteButton button", text: "Send KYC to Stakeholder", visible: :all)
  page.execute_script("arguments[0].click()", button)


  # click_on("Send KYC to Stakeholder")
  click_on("Proceed")
end

When('I log in as the investor user') do
  @user = @investor_user
  steps %(
    And I am at the login page
    When I fill and submit the login page
  )
end

When('I follow the KYC link from the email') do
  
  puts "Checking email for #{@investor_user.email}"
  open_email(@investor_user.email)
  @investor_kyc = InvestorKyc.last
  expect(current_email.subject).to include "Request to add KYC: #{@investor_kyc.entity.name}"
  visit(edit_investor_kyc_path(@investor_kyc))
end

Then('the {string} button should be disabled') do |string|
  expect(page).to have_button(string, disabled: true)
end

Then('the page should display the original CKYC details') do
  @investor_kyc.kyc_datas.each do |data|
    @kyc_data = data if data.address_match
    break if @kyc_data
  end
  steps %(
    Then the page should display the correct KYC details
  )
end


When('I am on the show page for {string}') do |string|
  @investor_kyc ||= InvestorKyc.last
  @kyc_data = @investor_kyc.reload.send("#{string.downcase}_data")
  visit(kyc_data_path(@kyc_data))
end

Then('I should be on the KYC edit page for fetching ckyc\/kra data') do
  expect(page).to have_content("CKYC")
  expect(page).to have_content("KRA")
end

Then('I should be on the {string} page') do |string|
  string = string.strip
  if string == "KRA result"
    expect(page).to have_content("KRA Data")
    expect(page).to have_content("Continue to Edit")
  elsif string == "Investor KYC edit"
    expect(page).to have_content("KYC Details")
    expect(page).to have_content("Kyc type")
  end
end



  def sample_kra_response
    {
      application_type: "I",
      application_number: "ABJPM6989J",
      pan_copy: "Y",
      exempt_status: "N",
      exempt_id_proof: "01",
      personal_information: {
        pan_number: "ABJPM6939J",
        name: "VINOD KUMAR SINGH",
        dob: "16/08/1955",
        gender: "M",
        father_name: "KUMAR MAGON",
        nationality: "01",
        residential_status: "R",
        uid_number: "N"
      },
      contact_information: {
        mobile_number: "9999999999",
        email_address: "ABC@ABC.COM",
        correspondence_address: {
          address_line1: "705 BHARTI APPARTMENT",
          address_line2: "PART-III PLOT NO-20",
          city: "FARIDABAD",
          state: "006",
          country: "101",
          pin_code: "121001",
          address_proof_date: "28/04/2014",
          address_proof: "09",
          address_reference: "2"
        },
        permanent_address: {
          address_line1: "#{Time.zone.now.strftime('%H:%M:%S')} 705 BHARTI APPARTMENT",
          address_line2: "PART-III PLOT NO-20",
          city: "FARIDABAD",
          state: "006",
          country: "101",
          pin_code: "121001",
          address_proof_date: "28/04/2014",
          address_proof: "09",
          address_reference: "2"
        }
      },
      financial_information: {
        income: "00",
        occupation: "99",
        other_occupation: ".",
        political_connection: "NA",
        net_worth_date: "01/01/1900"
      },
      request_tracing_details: {
        application_date: "19/03/2008",
        commencement_date: "01/01/1800",
        download_date: "22/05/2025 12:02:40",
        data_dump_type: "S"
      },
      fatca_details: {
        applicable: "N",
        date_declaration: "01-01-1900"
      },
      kra_information: {
        kra_info: "CVLKRA",
        request_date: "22/05/2025",
        response_date: "22/05/2025 12:02:40",
        total_records: "1"
      },
      kyc_information: {
        kyc_mode: "0",
        kyc_mode_description: "Normal KYC",
        ipv_flag: "Y",
        ipv_date: "13/05/2014",
        status: "Validated",
        status_code: "007",
        status_description: "KYC details have been successfully verified. Customer can start investing. ",
        status_date: "02/06/2023 17:15:24",
        document_proof: "S",
        internal_reference: "WEBSOLICIT",
        branch_code: "HEADOFFICE",
        marital_status: "01"
      },
      error_details: {
        error_description: "ERR-00000"
      },
      ref_id: "KCA2505221202383202QRC23TJWQ7C9U"
    }.to_json
  end

  def sample_ckyc_search_response
    {
      success: true,
      error_message: "string",
      search_response: {
        ckyc_number: Faker::Alphanumeric.alphanumeric(number: 10),
        masked_ckyc_no: "{CKYC Masked Number for example: XXXXXXXXXX1234}",
        name: "MR DINESH  RATHORE",
        fathers_name: "Mr TEJA  RAM RATHORE",
        age: "30",
        image_type: "jpg",
        photo: "{Base64 Value of Image}",
        kyc_date: "08-04-2017",
        updated_date: "08-04-2017",
        remarks: "string",
        ckyc_prefix: "NORMAL_ACCOUNT"
      },
      search_results: [
        {
          ckyc_number: Faker::Alphanumeric.alphanumeric(number: 10),
          masked_ckyc_no: "{CKYC Masked Number for example: XXXXXXXXXX1234}",
          name: "MR DINESH  RATHORE",
          fathers_name: "Mr TEJA  RAM RATHORE",
          age: "30",
          image_type: "jpg",
          photo: "{Base64 Value of Image}",
          kyc_date: "08-04-2017",
          updated_date: "08-04-2017",
          remarks: "string",
          ckyc_prefix: "NORMAL_ACCOUNT"
        }
      ]
    }.to_json
  end

  def sample_send_otp_response
    {
      success: true,
      message: "OTP has been sent to the registered mobile number XXXXXX6045",
      request_id: "123456"
    }.to_json
  end

  def sample_download_ckyc_response
    {
      success: true,
      download_response: {
        personal_details: {
          ckyc_number: Faker::Alphanumeric.alphanumeric(number: 10),
          ckyc_reference_id: "{CKYC_REFERENCE_ID}",
          type: "INDIVIDUAL/CORP/HUF etc",
          kyc_type: %w[normal ekyc minor].sample, # "normal/ekyc/minor",
          prefix: "MR",
          first_name: "DINESH",
          middle_name: "",
          last_name: "RATHORE",
          full_name: "MR DINESH RATHORE",
          maiden_prefix: "",
          maiden_first_name: "",
          maiden_middle_name: "",
          maiden_last_name: "",
          maiden_full_name: "",
          father_spouse_flag: "father/spouse",
          father_prefix: "Mr",
          father_first_name: "TEJA",
          father_middle_name: "",
          father_last_name: "RAM RATHORE",
          father_full_name: "Mr TEJA  RAM RATHORE",
          mother_prefix: "Mrs",
          mother_first_name: "",
          mother_middle_name: "",
          mother_last_name: "",
          mother_full_name: "",
          gender: "M",
          dob: "{}",
          pan: "{}",
          perm_address_line1: "#{Time.zone.now.strftime('%H:%M:%S')} BERA NAVODA",
          perm_address_line2: "BER KALAN",
          perm_address_line3: "JAITARAN",
          perm_address_city: "JAITARAN",
          perm_address_dist: "Pali",
          perm_address_state: "RJ",
          perm_address_country: "IN",
          perm_address_pincode: "306302",
          perm_current_same: "Y/N",
          corr_address_line1: "BERA NAVODA",
          corr_address_line2: "BER KALAN",
          corr_address_line3: "JAITARAN",
          corr_address_city: "JAITARAN",
          corr_address_dist: "Pali",
          corr_address_state: "RJ",
          corr_address_country: "IN",
          corr_address_pincode: "306302",
          mobile_no: "1234543215",
          email: "somegoodemail@GMAIL.COM",
          date: "02-04-2017",
          place: "Bangalore"
        },
        id_details: [
          {
            type: "PAN",
            id_no: "ABCDE1234F",
            ver_status: true
          }
        ],
        images: [
          {
            image_type: "PHOTO",
            type: "jpg/pdf",
            data: "{BASE64}"
          },
          {
            image_type: "PAN",
            type: "jpg/pdf",
            data: "{BASE64}"
          },
          {
            image_type: "AADHAAR/PASSPORT/VOTER/DL",
            type: "jpg/pdf",
            data: "{BASE64}"
          },
          {
            image_type: "SIGNATURE",
            type: "jpg/pdf",
            data: "{BASE64}"
          }
        ]
      }
    }.to_json
  end
