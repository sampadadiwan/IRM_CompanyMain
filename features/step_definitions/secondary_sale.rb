  include CurrencyHelper

  Given('I am at the sales page') do
    visit(secondary_sales_path)
  end

  When('I create a new sale {string}') do |arg1|
    @input_sale = FactoryBot.build(:secondary_sale)
    key_values(@input_sale, arg1)
    puts "\n####Input Sale####\n"
    puts @input_sale.to_json

    click_on("New Secondary Sale")
    fill_in("secondary_sale_name", with: @input_sale.name)
    fill_in("secondary_sale_start_date", with: @input_sale.start_date)
    fill_in("secondary_sale_offer_end_date", with: @input_sale.offer_end_date)
    fill_in("secondary_sale_end_date", with: @input_sale.end_date)
    fill_in("secondary_sale_percent_allowed", with: @input_sale.percent_allowed)
    fill_in("secondary_sale_support_email", with: @input_sale.support_email)
    click_on("Next")
    fill_in("secondary_sale_min_price", with: @input_sale.min_price)
    fill_in("secondary_sale_max_price", with: @input_sale.max_price)
    click_on("Next")
    click_on("Save")
    expect(page).to have_content("successfull")
    #sleep(1)
  end

  When('I visit the sale details page') do
    visit(secondary_sale_path(@sale))
  end

  Then('an sale should be created') do
    @sale = SecondarySale.last
    puts "\n####Sale####\n"
    puts @sale.to_json

    @sale.name.should == @input_sale.name
    @sale.start_date.should == @input_sale.start_date
    @sale.end_date.should == @input_sale.end_date
    @sale.percent_allowed.should == @input_sale.percent_allowed
    @sale.min_price.should == @input_sale.min_price
    @sale.max_price.should == @input_sale.max_price
    @sale.visible_externally.should == false
  end

  Then('I should see the sale details on the details page') do
    visit(secondary_sale_path(@sale))
    find(".show_details_link").click
    @input_sale ||= @sale # This is for times when the sale is not created from the ui in tests

    expect(page).to have_content(@input_sale.name)
    # expect(page).to have_content(@input_sale.start_date)
    expect(page).to have_content(@input_sale.end_date.strftime("%d/%m/%Y"))
    if @user.entity_id == @sale.entity_id
      expect(page).to have_content(custom_format_number(@input_sale.min_price, {}))
      expect(page).to have_content(custom_format_number(@input_sale.max_price, {}))
    end
    puts "\n####Sale####\n"
    puts @sale.to_json
  end

  Then('I should see the sale in all sales page') do
    visit(secondary_sales_path)
    @input_sale ||= @sale # This is for times when the sale is not created from the ui in tests

    expect(page).to have_content(@input_sale.name)
    expect(page).to have_content(@input_sale.start_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@input_sale.end_date.strftime("%d/%m/%Y"))
    if @user.entity_id == @sale.entity_id
      # expect(page).to have_content(@input_sale.percent_allowed)
      expect(page).to have_content(custom_format_number(@input_sale.min_price))
      expect(page).to have_content(custom_format_number(@input_sale.max_price))
    end
  end


  Then('the sale should become externally visible') do
    #sleep(1)
    @sale = SecondarySale.first
    puts "\n####Visible Sale####\n"
    puts "visible_externally = #{@sale.visible_externally}"
    find(".show_details_link").click
    @sale.visible_externally.should == true
    within("tr#visible_externally") do
        expect(page).to have_content("Yes")
    end
  end

  Given('there is a sale {string}') do |arg1|
    @sale = FactoryBot.build(:secondary_sale, entity: @entity)
    @sale.start_date = Time.zone.today
    key_values(@sale, arg1)
    SecondarySaleCreate.wtf?(secondary_sale: @sale, current_user: @user)
    key_values(@sale, arg1)
    puts @sale.to_json
    @sale.save!
    @sale.reload
    puts "\n####Sale####\n"
    puts @sale.to_json
    puts "@sale.active? = #{@sale.active?}"
  end

  Given('params {string} are set for the sale') do |args|
    key_values(@sale, args)
    puts @sale.to_json
    @sale.save!
    @sale.reload
  end


  Given('I am at the sales details page') do
    visit secondary_sale_path(@sale)
  end


Given('I have {string} access to the sale') do |metadata|

  investor = Investor.where(investor_entity_id: @user.entity_id, entity_id: @entity.id).first
  ar = AccessRight.create!(entity: @entity, owner: @sale, access_type: "SecondarySale",
          access_to_investor_id: investor.id, metadata: metadata)

  puts "\n####AccessRight####\n"
  puts ar.to_json
  puts "\n####InvestorAccess####\n"
  puts InvestorAccess.all.to_json
end


Then('the sales total_offered_quantity should be {string}') do |arg|
  @sale.reload
  @sale.total_offered_quantity.should == arg.to_i
end


Given('I should have {string} access to the sale {string}') do |access_type, arg|
  puts "Checking access #{access_type} on fund #{@sale} for #{@user} as #{arg}"
  Pundit.policy(@user, @sale).send("#{access_type}?").to_s.should == arg
end

Then('user {string} have {string} access to the offer') do |truefalse, offer_access|
  offer_access.split(",").each do |access|
    puts "##Checking access #{access} on offer #{@offer} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @offer).send("#{access}?").to_s.should == truefalse
  end
end

Then('user {string} have {string} access to the interest') do |truefalse, interest_access|
  interest_access.split(",").each do |access|
    puts "##Checking access #{access} on interest #{@interest} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @interest).send("#{access}?").to_s.should == truefalse
  end
end

Given('another user should have {string} access to the sale {string}') do |access_type, truefalse|
  puts "##Checking access #{access_type} on interest #{@sale} for #{@another_user.email} as #{truefalse}"
  Pundit.policy(@another_user, @sale).send("#{access_type}?").to_s.should == truefalse
end

Given('employee investor should have {string} access to the sale {string}') do |access_type, truefalse|
  @employee_investor = @investor_entity.employees.first
  puts "##Checking access #{access_type} on interest #{@sale} for #{@employee_investor.email} as #{truefalse}"
  Pundit.policy(@employee_investor, @sale).send("#{access_type}?").to_s.should == truefalse
end


Given('existing investors have {string} access rights to the sale') do |metadata|

  @entity.investors.each do |inv|
    if @sale.access_rights.where(access_to_investor_id: inv.id).empty?
      @access_right = AccessRight.create!(owner: @sale, access_type: "SecondarySale", metadata: metadata,
        entity: @entity, access_to_investor_id: inv.id)

      inv.investor_entity.employees.each do |emp|
        ia = InvestorAccess.create(investor:inv, user: emp,
                    last_name: emp.last_name,
                    first_name: emp.first_name,
                    email: emp.email,  approved: true,
                    entity_id: @sale.entity_id)
        puts "\n####InvestorAccess####\n"
        puts ia.to_json
      end

      puts "\n####Investor AccessRight####\n"
      puts @access_right.to_json

    else
      puts "Skipping access right for investor #{inv.investor_name}, alread has access"
    end
  end
end





############################################################################
############################################################################
#######################  Investor related test steps #############################
############################################################################
############################################################################


Given('my firm is an investor in the company') do
  @company = Entity.startups.first
  @investor = Investor.create!(investor_name: @entity.name, pan: @entity.pan,
                               primary_email: @entity.primary_email, entity: @company,
                               investor_entity: @entity, category: "Lead Investor")

  InvestorAccess.create!(investor:@investor, user: @user,
    first_name: @user.first_name,
    last_name: @user.last_name,
    email: @user.email, approved: true,
    entity_id: @company.id)


end

Given('I should not see the sale in all sales page') do
  visit(secondary_sales_path)
end

Given('I should not see the sale details on the details page') do
  expect(page).to have_no_content(@sale.name)
end

Given('the investor has {string} access rights to the sale') do |metadata|
  @access_right = AccessRight.create!(owner: @sale, entity_id: @sale.entity_id, access_to_investor_id: @investor.id, metadata: metadata, access_type: "SecondarySale")

  puts "\n####Investor AccessRight####\n"
  puts @access_right.to_json
  @sale.reload
end

Given('there are {string} investments {string} in the company') do |count, args|
  (1..count.to_i).each do
    i = FactoryBot.build(:investment, entity: @company, investor: @investor,
      funding_round: @funding_round)
    key_values(i, args)
    SaveInvestment.wtf?(investment: i).success?.should == true
    puts "\n####Investment Created####\n"
    puts i.to_json
  end
end

Then('I should see the offer') do
  @offer = Offer.last

  @offer.user_id.should == @user.id
  @offer.secondary_sale_id.should == @sale.id
  @offer.entity_id.should == @company.id
  expect(page).to have_content(@user.full_name)
  expect(page).to have_content(@company.name)
  expect(page).to have_content(@sale.name)
  expect(page).to have_content("No")
end

Then('the sale offer amount must not be updated') do
  @sale.reload
  puts @sale.to_json
  @sale.total_offered_quantity.should_not == @offer.quantity
end

Then('the sale offer amount must be updated') do
  @sale.reload
  puts @sale.to_json
  @sale.total_offered_quantity.should == @offer.quantity
end

Then('when the offer is approved') do
  @offer = Offer.last
  puts @offer.to_json
  OfferApprove.wtf?(offer: @offer, current_user: @user)
end



Given('there are offers {string} for the sale') do |args|
  Investor.all.each do |inv|
    offer = FactoryBot.build(:offer,investor: inv, entity: inv.entity, secondary_sale: @sale,
                          user: inv.investor_entity.employees.sample)


    key_values(offer, args)
    approved = offer.approved
    OfferCreate.wtf?(offer: offer, current_user: @user).success?
    OfferApprove.wtf?(offer: offer, current_user: @user) if approved
    puts "\n####Offer Created####\n"
    puts offer.to_json
  end
end


Then('I should be able to create an interest in the sale') do

  puts @user.to_json

  visit(secondary_sale_path(@sale))
  click_on("New Interest")
  fill_in("interest_quantity", with: @sale.total_offered_quantity)
  fill_in("interest_price", with: @sale.min_price)
  click_on("Save")
  expect(page).to have_content("successfull")
  #sleep(1)
end


Given('there are {string} interests {string} for the sale') do |count, args|

  @sale.reload

  (1..count.to_i).each do
    investor_entity = FactoryBot.create(:entity, entity_type: "Family Office")
    investor = FactoryBot.create(:investor, entity: @sale.entity, investor_entity: investor_entity)

    ar = AccessRight.create(owner: @sale, access_type: "SecondarySale", metadata: "Buyer",
    entity: @entity, access_to_investor_id: investor.id)

    puts "\n####AccessRight####\n"
    puts ar.to_json


    user = FactoryBot.create(:user, entity: investor_entity)
    ia = InvestorAccess.create!(entity: @entity, investor: investor,
        first_name: user.first_name, last_name: user.last_name,
        email: user.email, granter: user, approved: true )

    puts "\n####Investor Access####\n"
    puts ia.to_json

    interest = Interest.new(secondary_sale: @sale,
                  user: user,
                  quantity: @sale.total_offered_quantity,
                  price: @sale.min_price,
                  entity: @entity,
                  interest_entity: investor_entity,
                  short_listed_status: Interest::STATUS_SHORT_LISTED,
                  buyer_signatory_emails: "shrikant.gour@caphive.com")

    key_values(interest, args)
    interest.save!
    puts "\n####Interest Created####\n"
    puts interest.to_json
  end

end

Given('the offers have no signatories') do
  @sale.offers.update_all(seller_signatory_emails: nil)
end

Given('the interests have no signatories') do
  @sale.interests.update_all(buyer_signatory_emails: nil)
end


Then('when the allocation is done') do
  NewAllocationJob.perform_now(@sale.id, @user.id, "Default Allocation Engine", priority: "Time", matching_priority: "Supply Driven")
  @sale.reload
  puts "\n####Sale Reloaded####\n"
  puts @sale.to_json
end

Then('the sale must be allocated correctly') do
  @sale.total_offered_quantity.should == @sale.offers.approved.sum(:quantity)
  # @sale.total_offered_amount_cents.should == @sale.offers.approved.sum(:amount_cents)
  # @sale.total_interest_amount_cents.should == @sale.interests.short_listed.sum(:amount_cents)
  @sale.total_interest_quantity.should == @sale.interests.short_listed.sum(:quantity)
  @sale.allocation_quantity.should == @sale.offers.approved.sum(:allocation_quantity)
  @sale.allocation_quantity.should == @sale.interests.short_listed.sum(:allocation_quantity)
  @sale.allocation_interest_amount_cents.should == @sale.interests.short_listed.sum(:allocation_amount_cents)

  @sale.allocation_offer_amount_cents.should == @sale.offers.approved.sum(:allocation_amount_cents)
end


Then('the offers must be allocated correctly') do
  @sale.offers.approved.each do |offer|
    if @sale.cmf_allocation_percentage[offer.custom_matching_vals] <= 1
      offer.allocation_percentage.should == @sale.cmf_allocation_percentage[offer.custom_matching_vals] * 100
    else
      offer.allocation_percentage.should == 100.0
    end
    # puts offer.to_json
    offer.allocation_quantity.should == (offer.quantity * offer.allocation_percentage / 100).ceil
  end
end

Then('the interests must be allocated correctly') do
  @sale.interests.short_listed.each do |interest|
    if @sale.cmf_allocation_percentage[interest.custom_matching_vals] <= 1
      interest.allocation_percentage.should == 100.0
    else
      interest.allocation_percentage.should be_within(0.1).of(100.0 / @sale.cmf_allocation_percentage[interest.custom_matching_vals])
    end
    # puts interest.to_json
    interest.allocation_quantity.should  == (interest.quantity * interest.allocation_percentage / 100).ceil
  end
end

Then('when the sale is finalized') do
  @sale.finalized = true
  @sale.final_price = 100
  @sale.save!
  @sale.reload
end

Then('when the cap table is updated from the sale') do
  CapTableFromSaleJob.new.perform(@sale.id)
end

Then('there are {string} investor investments in the cap table') do |count|
  investor_ids = Investor.all.collect(&:id)
  Investment.where(investor_id: investor_ids).count.should == count.to_i
end

Then('the investor investments quantity should be the interest quantity') do
  investor_ids = Investor.all.collect(&:id)
  Investment.where(investor_id: investor_ids).sum(:quantity).should == Interest.short_listed.escrow_deposited.sum(:quantity)
end

Then('the offers completetion page must be visible') do
  visit offers_secondary_sale_path(@sale, report: "completion_report")
  @sale.offers.each do |offer|
    within "#offer_#{offer.id}" do
      expect(page).to have_content(offer.user.full_name)
      expect(page).to have_content(offer.id)
      expect(page).to have_content(offer.user.email)
    end
  end
end

Given('advisor is {string} advisor access to the sale') do |given|
  @user = @employee_investor

    if given == "given" || given == "yes"

          # Create the Investor Advisor
          investor_advisor = InvestorAdvisor.create!(entity_id: @entity.id, email: @user.email)
          investor_advisor.permissions.set(:enable_secondary_sale)
          investor_advisor.save

          puts "\n####Investor Advisor####\n"
          puts investor_advisor.to_json

          # Switch the IA to the entity
          investor_advisor.switch(@user)

          # Create the Access Right
          @access_right = AccessRight.create!(entity_id: @entity.id, owner: @sale, user_id: @user.id, metadata: "Investor Advisor")
          @access_right.save


          puts "\n####Access Right####\n"
          ap @access_right

    end
end

Given('the advisor has role {string}') do |roles|
  @user = @employee_investor
  steps %(
    Given the user has role "#{roles}"
  )
end


Given('I am {string} employee access to the sale') do |given|
  if given == "given" || given == "yes"
    @access_right = AccessRight.create!(entity_id: @sale.entity_id, owner: @sale, user_id: @user.id)
    puts "####### Employee AccessRight #######\n"
    puts @access_right.to_json
  end
end

Given('the sale access right has access {string}') do |crud|
  if @access_right
    crud.split(",").each do |p|
      @access_right.permissions.set(p.to_sym)
    end
    @access_right.save!
    @user.reload
    puts "####### AccessRight Permissions #######\n"
    ap @access_right
  end
end

Then('user {string} have {string} access to the sale') do |truefalse, accesses|
  accesses.split(",").each do |access|
    puts "##Checking access #{access} on fund #{@sale.name} for #{@user.email} as #{truefalse}"
    Pundit.policy(@user, @sale).send("#{access}?").to_s.should == truefalse
  end
end



Then('existing investor user {string} have {string} access to the sale') do |truefalse, accesses|
  @employee_investor.reload
  accesses.split(",").each do |access|
    puts "##Checking access #{access} on fund #{@sale.name} for #{@employee_investor.email} as #{truefalse}"
    Pundit.policy(@employee_investor, @sale).send("#{access}?").to_s.should == truefalse
  end
end

Given('the sale has a SPA template') do
  doc = Document.new(entity_id: @sale.entity_id, owner: @sale, name: "SPA", user: User.first, owner_tag: "Offer Template")
  doc.file = File.open("public/sample_uploads/Purchase-Agreement-1.docx", "rb")
  doc.save!
end

Given('the sale has an allocation SPA template') do
  doc = Document.new(entity_id: @sale.entity_id, owner: @sale, name: "SPA", user: User.first, owner_tag: "Allocation Template")
  doc.file = File.open("public/sample_uploads/Purchase-Agreement-1.docx", "rb")
  doc.save!
end


Then('when the offers are verified') do
  @sale.offers.not_verified.each do |offer|
    OfferVerify.wtf?(offer: offer, current_user: @user)
  end
end


Then('when the allocations are verified') do
  @sale.allocations.unverified.each do |allocation|
    allocation.verified = true
    allocation.save!
  end
end

Then('when the allocations SPA generation is triggered') do
  AllocationSpaJob.perform_now(@sale.id, nil, @user.id)
end

Then('the SPAs must be generated for each verified allocation') do
  @sale.reload
  @sale.allocations.verified.each do |allocation|
    allocation.documents.where(name: "SPA #{allocation.offer.full_name} #{allocation.interest.buyer_entity_name}").to_a.should_not == []
  end
end

Given('we trigger a notification {string} for the sale') do |notification|
  puts "\nTriggering notification #{notification}"
  visit secondary_sale_path(@sale)
  sleep 1
  click_on "Notifications"
  click_on notification
  sleep 1
  click_on "Proceed"
  sleep 1
end

Then('each seller must receive email with subject {string}') do |eval_subject|
  subject = eval("\"" + eval_subject + "\"")

  all_emails = @sale.investor_users("Seller").collect(&:email).flatten 

  puts "All emails #{all_emails.uniq}"

  @sale.investor_users("Seller").collect(&:email).each do |email|
    #sleep(1)
    puts "Checking investor email #{email} with subject #{subject}"
    open_email(email)
    expect(current_email.subject).to eq subject
  end
  
end

Then('each buyer must receive email with subject {string}') do |eval_subject|
  subject = eval("\"" + eval_subject + "\"")

  all_emails = @sale.investor_users("Buyer").collect(&:email).flatten 

  puts "All emails #{all_emails.uniq}"

  @sale.investor_users("Buyer").collect(&:email).each do |email|
    puts "Checking investor email #{email} with subject #{subject}"
    open_email(email)
    expect(current_email.subject).to eq subject
  end

end


Then('when the sellers are notified on the SPA') do
  @sale.notify_spa_sellers
end

When('the adhaar esign is triggered') do
  @sale.offers.verified.each do |offer|
    OfferEsignGenerateJob.perform_later(offer.id)
  end
end


Then('I should see the esign link on the offer page') do
  visit(offer_path(@user.offers.first))
end


Given('when I click the esign link') do
  click_on "eSign SPA"
end

Then('I should be sent to the digio esign page') do
  sleep 10
  expect(page).to have_content("Security code sent to #{@user.phone}")
end


Given('that the adhaar esign has values {string}') do |args|
  @adhaar_esign = AdhaarEsign.last
  key_values(@adhaar_esign, args)
  @adhaar_esign.save
end

When('the esign is completed') do
  AdhaarEsignCompletedJob.perform_now(@adhaar_esign.id)
end

Then('the SPA should be marked as accepted and signed') do
  @signed_offer = AdhaarEsign.last.owner
  @signed_offer.final_agreement.should == true
  @signed_offer.esign_completed.should == true
end

Then('the seller must receive email with subject {string}') do |subject|
  open_email(@signed_offer.user.email)
  expect(current_email.subject).to include subject
end

Given('the investors are added to the sale') do
  @user.entity.investors.each do |inv|
    ar = AccessRight.create!( owner: @sale, access_type: "SecondarySale",
                             access_to_investor_id: inv.id, entity: @user.entity)


    puts "\n####Granted Access####\n"
    puts ar.to_json
  end
end

Then('the document folder should be different for the new sale') do
  @sale_new = SecondarySale.last
  @sale_new.id.should_not == @sale.id
  @sale_new.name.should == @sale.name
  @sale_new.document_folder_id.should_not == @sale.document_folder_id
end


Given('the investor has an offer {string} for the sale') do |args|
  @offer = FactoryBot.build(:offer, entity: @sale.entity, secondary_sale: @sale,
                          user: @employee_investor, investor: @investor)
  key_values(@offer, args)
  @offer.save!
  puts "\n####Offer Created####\n"
  puts @offer.to_json
end

Given('the offer is approved') do
  OfferApprove.wtf?(offer: @offer, current_user: @user)
end

Given('the investor has an interest {string} for the sale') do |args|
  @interest = FactoryBot.build(:interest, secondary_sale: @sale.reload, price: @sale.min_price,
                          user: @employee_investor, entity: @sale.entity, interest_entity: @investor.investor_entity)

  key_values(@interest, args)
  @interest.save!
  puts "\n####Interest Created####\n"
  puts @interest.to_json
end




Then('the allocations must be visible') do
  visit(secondary_sale_path(@sale))
  click_on("View Allocations")
  click_on("All Allocations")
  @sale.allocations.each_with_index do |allocation, idx|
    puts "Checking allocation #{allocation} with id #{allocation.id}"
    within("#allocation_#{allocation.id}") do
      expect(page).to have_content(allocation.offer.full_name)
      expect(page).to have_content(allocation.interest.buyer_entity_name)
      expect(page).to have_content(allocation.quantity)
      expect(page).to have_content(money_to_currency(allocation.amount, {}))
      expect(page).to have_content(allocation.offer.full_name)
      expect(page).to have_content(custom_format_number(allocation.offer.quantity))
      expect(page).to have_content(custom_format_number(allocation.offer.price))
      expect(page).to have_content(allocation.interest.buyer_entity_name)
      expect(page).to have_content(custom_format_number(allocation.interest.quantity))
      expect(page).to have_content(custom_format_number(allocation.interest.price))
      expect(page).to have_content(allocation.verified ? "Yes" : "No")
    end

    if idx == 9
      within('.pagination') do
        click_link '2'
      end
    end
  end
end

Then('the sale must be allocated as per the file {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  allocations = @sale.allocations.order(id: :asc).to_a

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    allocation = allocations[idx-1]
    puts "Checking #{allocation}"
    allocation.offer.full_name.should == user_data["Offer"]
    allocation.offer.price.should == user_data["Offer Price"].to_i
    allocation.offer.quantity.should == user_data["Offer Quantity"].to_i

    allocation.interest.buyer_entity_name.should == user_data["Interest"]
    allocation.interest.price.should == user_data["Interest Price"].to_i
    allocation.interest.quantity.should == user_data["Interest Quantity"].to_i

    allocation.quantity.should == user_data["Allocation Quantity"].to_i
    allocation.amount.to_d.should == user_data["Allocation Amount"].to_i

    allocation.verified.should == (user_data["Verified"] == "Yes")

  end
end


Then('when the allocations are verified {string}') do |verified|
  # binding.pry
  visit(secondary_sale_path(@sale))
  click_on("View Allocations")
  click_on("All Allocations")
  sleep(1)
  click_on("Bulk Actions")
  if verified == "true"
    click_on("Verify")
  else
    click_on("Unverify")
  end
  sleep(1)
  click_on("Proceed")
  sleep(12)
  @sale.reload
end

Then('the allocations must be verified {string}') do |verified|
  @sale.allocations.each do |allocation|
    puts "Checking allocation #{allocation} #{verified}"
    allocation.verified.should == (verified == "true")
  end
end

Then('the corresponding offers must verified {string}') do |verified|
  @sale.allocations.each do |allocation|
    puts "Checking offer #{allocation.offer} #{verified}"
    allocation.offer.verified.should == allocation.verified
    allocation.offer.verified.should == (verified == "true")
    allocation.offer.allocation_quantity.should == allocation.offer.allocations.verified.sum(:quantity)
  end
end

Then('the corresponding interests must verified {string}') do |verified|
  @sale.allocations.each do |allocation|
    puts "Checking interest #{allocation.interest} #{verified}"
    allocation.interest.verified.should == allocation.verified
    allocation.interest.verified.should == (verified == "true")
    allocation.interest.allocation_quantity.should == allocation.interest.allocations.verified.sum(:quantity)
  end
end
