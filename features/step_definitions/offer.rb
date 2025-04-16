  Given('Im logged in as an investor') do

    @user = @investor_user
    steps %(
        And I am at the login page
        When I fill and submit the login page
    )

  end

  Then('I edit the offer {string}') do |arg|
    visit(edit_offer_path(@offer))

    @offer = FactoryBot.build(:offer, approved: @offer.approved, secondary_sale: @offer.secondary_sale)
    key_values(@offer, arg)

    steps %(
      Then when I submit the offer
    )
  end


  Then('when I submit the offer') do

    puts "\n####Offer####\n"
    puts @offer.to_json

    fill_in("offer_quantity", with: @offer.quantity) unless @offer.approved
    fill_in("offer_full_name", with: @offer.full_name)

    if(@offer.secondary_sale && @offer.secondary_sale.finalized)
      click_on("Next")      
      fill_in("offer_PAN", with: @offer.PAN)
      fill_in("offer_address", with: @offer.address)
      # fill_in("offer_city", with: @offer.city)
      # fill_in("offer_demat", with: @offer.demat)
      fill_in("offer_bank_account_number", with: @offer.bank_account_number)
      fill_in("offer_ifsc_code", with: @offer.ifsc_code)
      # fill_in("offer_bank_name", with: @offer.bank_name)
      # fill_in("offer_bank_routing_info", with: @offer.bank_routing_info)
      click_on("Next")
    end

    click_on("Save")
    expect(page).to have_content("successfull")
    # sleep(1)

  end

  Then('when I place an offer {string} from the offers tab') do |arg|
    @offer = FactoryBot.build(:offer)
    key_values(@offer, arg)
    click_on("New")
    steps %(
      Then when I submit the offer
    )
  end

  When('I visit the offer details page') do
    @offer ||= Offer.first
    visit(offer_path(@offer))
  end


  Then('I should see the offer details') do
    if page.has_css?("#display_status_ok")
      #sleep(1)
      find("#display_status_ok").click
    end

    expect(page).to have_content(@user.full_name)
    expect(page).to have_content(@entity.name)
    expect(page).to have_content(@sale.name)
    expect(page).to have_content(@offer.quantity)

    if(@offer.secondary_sale && @offer.secondary_sale.finalized)
      expect(page).to have_content(@offer.full_name)
      expect(page).to have_content(@offer.PAN)
      expect(page).to have_content(@offer.address)
      expect(page).to have_content(@offer.bank_account_number)
      # expect(page).to have_content(@offer.bank_name)
      # expect(page).to have_content(@offer.bank_routing_info)
    end

    within("tr#approved") do
        expect(page).to have_content(@offer.approved ? "Yes" : "No")
    end

    @offer = Offer.last
  end

  Then('when the offer sale is finalized') do
    @offer.secondary_sale.finalized = true
    @offer.secondary_sale.lock_allocations = true

    @offer.secondary_sale.final_price = 100
    @offer.secondary_sale.save
  end

  Then('I should see the offer in the offers tab') do
    visit(secondary_sale_path(@sale))
    click_on("Offers")
    # Check if this has the card class
    if @offer.full_name.present?
      expect(page).to have_content(@offer.full_name)  
    else
      expect(page).to have_content(@user.full_name)
    end
    # expect(page).to have_content(@entity.name)
    # expect(page).to have_content(@offer.quantity)
    expect(page).to have_content(@offer.allocation_quantity)
    # within("td.approved") do
        # expect(page).to have_content("No")
    # end
  end


Given('there are {string} offer {string} for each investor') do |approved_arg, args|
  approved = approved_arg == "approved"
  Investor.all.each do |h|
    offer = FactoryBot.build(:offer, user_id:h.investor_entity.employees.sample.id, entity_id: @sale.entity_id, secondary_sale_id: @sale.id, investor_id: h.id, approved: approved)
    key_values(offer, args)
    offer.save!

    offer.approved = approved
    offer.save

    puts "\n####Offer####\n"
    puts offer.to_json
  end

  @sale.reload
end

Then('I should see all the offers') do
  click_on("Offers")

  Offer.all.each do |offer|
    within("tr#offer_#{offer.id}") do
        expect(page).to have_content(offer.user.full_name)
        expect(page).to have_content(offer.investor.investor_name)
        expect(page).to have_content(offer.quantity)
        expect(page).to have_content(offer.percentage)
        # within("td.approved") do
          if offer.approved
            expect(page).to have_content("Yes")
          else
            expect(page).to have_content("No")
          end
        # end
    end
  end
end

Then('When I approve the offers the offers should be approved') do
Offer.all.each do |offer|
    visit offer_path(offer)
    click_on("Approve")
    sleep(1)

    offer.reload
    offer.approved.should == true

    within("td.approved") do
      expect(page).to have_content("Yes")
    end

    visit secondary_sale_path(offer.secondary_sale)
    click_on("Offers")
  end
end

Given('Given I upload a offer file {string}') do |file_name|

    @import_offer_file_name = file_name
    @existing_user_count = User.count
    visit(secondary_sale_path(@sale))
    click_on("Offers")
    click_on("Upload / Download")
    click_on("Upload Offers")
    fill_in('import_upload_name', with: "Test Upload")
    attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
    sleep(4)
    click_on("Save")
    expect(page).to have_content("Import Upload:")
    #sleep(4)
    ImportUploadJob.perform_now(ImportUpload.last.id)
    #sleep(5)

    ImportUpload.last.failed_row_count.should == 0
end

Then('when the offers are approved') do
  @sale.reload
  @sale.offers.each do |offer|
    offer.granted_by_user_id = @user.id
    OfferApprove.wtf?(offer: offer, current_user: @user).success?.should == true
  end
end

Then('offer approval notification is sent') do
  @sale.offers.each do |offer|
    offer.notify_approval
  end
end

Then('the notification should be sent successfully') do
  OfferNotifier::Notification.count.should == @sale.offers.count
end

Then('the sale offered quantity should be {string}') do |quantity|
  @sale.reload
  @sale.total_offered_quantity.should == quantity.to_i
end


Then('the offers must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_offer_file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  offers = @sale.offers.order(id: :asc).to_a

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    offer = offers[idx-1]
    puts "Checking import of #{offer}"
    offer.quantity.should == user_data["Quantity"]
    offer.offer_type.should == user_data["Founder/Employee/Investor"]
    offer.investor.investor_name.should == user_data["Investor"] if offer.offer_type == "Investor"
    offer.user.email.should == user_data["Email"]
    offer.address.should == user_data["Address"]
    offer.PAN.should == user_data["Pan"]
    offer.seller_signatory_emails.should == user_data["Seller Signatory Emails"]
    offer.bank_account_number.should == user_data["Bank Account"].to_s
    offer.ifsc_code.should == user_data["Ifsc Code"]
    offer.demat.should == user_data["Demat"].to_s
    offer.city.should == user_data["City"]
  end
end

Given('Offer PAN verification is enabled') do
  @sale.entity.entity_setting.update!(pan_verification: true)
  @sale.update!(disable_pan_kyc: false)
end

Given('I add pan details to the offer') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  @og_pan_verification_response = @offer.pan_verification_response

  @offer.update!(approved: true)
  visit(edit_offer_path(@offer))
  fill_in("offer_full_name", with: Faker::Name.unique.name)
  click_on("Next")  
  fill_in("offer_PAN", with: Faker::Alphanumeric.alphanumeric(number: 10).upcase)
  attach_file("files[]", File.absolute_path("./public/sample_uploads/example_pan.jpeg"), make_visible: true)
  sleep(1)
  click_on("Next")
  click_on("Save")
  expect(page).to have_content("successfull")
end

Then('Pan Verification is triggered') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  sleep(5)
  @offer.reload.pan_verification_response.should_not == @og_pan_verification_response
end

Then('when the offer name is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @og_pan_verification_response = @offer.pan_verification_response
  @og_bank_verification_response = @offer.bank_verification_response

  @offer.update!(approved: true)
  visit(edit_offer_path(@offer))
  fill_in("offer_full_name", with: Faker::Name.unique.name)
  click_on("Next")  
  click_on("Next")
  click_on("Save")
end

Then('when the offer PAN is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_pan_card).and_return(pan_response)
  @og_pan_verification_response = @offer.pan_verification_response
  @offer.update!(approved: true)
  visit(edit_offer_path(@offer))
  click_on("Next")
  fill_in("offer_PAN", with: Faker::Alphanumeric.alphanumeric(number: 10).upcase)
  click_on("Next")
  click_on("Save")
end

Given('Offer Bank verification is enabled') do
  @sale.entity.entity_setting.update!(bank_verification: true)
  @sale.update!(disable_bank_kyc: false)
end

Given('I add bank details to the offer') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @og_bank_verification_response = @offer.bank_verification_response

  @offer.update!(approved: true)
  visit(edit_offer_path(@offer))
  fill_in("offer_full_name", with: Faker::Name.unique.name)
  click_on("Next")  
  fill_in("offer_address", with: @offer.address)
  fill_in("offer_bank_account_number", with: Faker::Bank.unique.account_number)
  fill_in("offer_ifsc_code", with: Faker::Bank.swift_bic)
  click_on("Next")
  click_on("Save")
end

Then('Bank Verification is triggered') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  sleep(5)
  @offer.reload
  @offer.bank_verification_response.should_not == @og_bank_verification_response
end

Then('when the offer Bank Account number is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @og_bank_verification_response = @offer.bank_verification_response

  @offer.update!(approved: true)
  visit(edit_offer_path(@offer))
  click_on("Next")
  fill_in("offer_bank_account_number", with: Faker::Bank.unique.account_number)
  click_on("Next")
  click_on("Save")
end

Then('when the offer Bank IFSC is updated') do
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response)
  @og_bank_verification_response = @offer.bank_verification_response

  visit(edit_offer_path(@offer))
  click_on("Next")
  fill_in("offer_ifsc_code", with: Faker::Bank.swift_bic)
  click_on("Next")
  click_on("Save")
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


Then('the offer investors must have access rights to the sale') do
  @sale.reload
  @sale.offers.each do |offer|
    offer.investor.access_rights.where(owner: @sale).count.should == 1
  end
end