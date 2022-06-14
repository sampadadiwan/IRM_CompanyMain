  include InvestmentsHelper

  Given('I am at the sales page') do
    visit(secondary_sales_path)
  end
  
  When('I create a new sale {string}') do |arg1|
    @input_sale = FactoryBot.build(:secondary_sale)
    key_values(@input_sale, arg1)
    puts "\n####Sale####\n"
    puts @input_sale.to_json
    
    click_on("New Secondary Sale")
    fill_in("secondary_sale_name", with: @input_sale.name)
    fill_in("secondary_sale_start_date", with: @input_sale.start_date.strftime("%d/%m/%Y"))
    fill_in("secondary_sale_end_date", with: @input_sale.end_date.strftime("%d/%m/%Y"))
    fill_in("secondary_sale_percent_allowed", with: @input_sale.percent_allowed)
    click_on("Next")    
    fill_in("secondary_sale_min_price", with: @input_sale.min_price)
    fill_in("secondary_sale_max_price", with: @input_sale.max_price)
    click_on("Next")
    click_on("Save") 
    sleep(1)  
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
    @input_sale ||= @sale # This is for times when the sale is not created from the ui in tests

    expect(page).to have_content(@input_sale.name)
    expect(page).to have_content(@input_sale.start_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@input_sale.end_date.strftime("%d/%m/%Y"))
    if @user.entity_id == @sale.entity_id
      expect(page).to have_content(@input_sale.percent_allowed)
      expect(page).to have_content(@input_sale.min_price)
      expect(page).to have_content(@input_sale.max_price)
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
      expect(page).to have_content(@input_sale.min_price)
      expect(page).to have_content(@input_sale.max_price)
    end
  end
  
  
  Then('the sale should become externally visible') do
    sleep(1)
    @sale = SecondarySale.first
    puts "\n####Visible Sale####\n"
    puts "visible_externally = #{@sale.visible_externally}"

    @sale.visible_externally.should == true
    within("tr#visible_externally") do
        expect(page).to have_content("Yes")
    end
  end
  
  Given('there is a sale {string}') do |arg1|
    @sale = FactoryBot.build(:secondary_sale, entity: @entity)
    @sale.start_date = Time.zone.today    
    key_values(@sale, arg1)
    @sale.save!
    @sale.reload
    puts "\n####Sale####\n"
    puts @sale.to_json
    puts "@sale.active? = #{@sale.active?}"
  end
  
  Given('I am at the sales details page') do
    visit secondary_sale_path(@sale)
  end
  
  Then('I should see the holdings') do
    Holding.all.each do |h|
        within("tr#holding_#{h.id}") do
            expect(page).to have_content(h.holding_type)
            expect(page).to have_content(h.user.full_name)
            # expect(page).to have_content(h.user.email)
            # expect(page).to have_content(h.entity.name)
            expect(page).to have_content(h.investment_instrument)
            expect(page).to have_content(h.quantity)
        end
    end
  end
  


Given('I have {string} access to the sale') do |metadata|
  
  investor = Investor.where(investor_entity_id: @user.entity_id, investee_entity_id: @entity.id).first
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
  Pundit.policy(@user, @sale).send("#{access_type}?").to_s.should == arg
end

Given('another user should have {string} access to the sale {string}') do |access_type, arg|
  Pundit.policy(@another_user, @sale).send("#{access_type}?").to_s.should == arg
end

Given('employee investor should have {string} access to the sale {string}') do |access_type, arg|
  @employee_investor = @investor_entity.employees.first    
  Pundit.policy(@employee_investor, @sale).send("#{access_type}?").to_s.should == arg
end


Given('employee investor has {string} access rights to the sale') do |metadata|
  ar = AccessRight.create(owner: @sale, access_type: "SecondarySale", metadata: metadata,
    entity: @entity, access_to_investor_id: @holdings_investor.id)

  
  puts "\n####AccessRight xxx ####\n"
  puts ar.to_json
    
end

Given('existing investor has {string} access rights to the sale') do |metadata|
  ar = AccessRight.create(owner: @sale, access_type: "SecondarySale", metadata: metadata,
    entity: @entity, access_to_investor_id: @investor.id)

  
  ia = InvestorAccess.create!(investor:@investor, user: @employee_investor, 
              last_name: @employee_investor.last_name, 
              first_name: @employee_investor.first_name, 
              email: @employee_investor.email,  approved: true, 
              entity_id: @sale.entity_id)

  puts "\n####AccessRight####\n"
  puts ar.to_json
  puts "\n####InvestorAccess####\n"
  puts ia.to_json
    
end



############################################################################
############################################################################
#######################  VC related test steps #############################  
############################################################################
############################################################################





Given('my firm is an investor in the startup') do
  @startup = Entity.startups.first
  @investor = Investor.create!(investee_entity: @startup, investor_entity: @entity, category: "Lead Investor")

  InvestorAccess.create!(investor:@investor, user: @user, 
    first_name: @user.first_name, 
    last_name: @user.last_name,
    email: @user.email, approved: true, 
    entity_id: @startup.id)

  puts @investor.to_json
end

Given('I should not see the sale in all sales page') do
  visit(secondary_sales_path)
end

Given('I should not see the sale details on the details page') do
  expect(page).to have_no_content(@sale.name)
end

Given('the investor has {string} access rights to the sale') do |metadata|
  AccessRight.create!(owner: @sale, access_to_investor_id: @investor.id, metadata: metadata,
      access_type: "SecondarySale", entity: @startup)
end

Given('there are {string} investments {string} in the startup') do |count, args|
  (1..count.to_i).each do 
    i = FactoryBot.build(:investment, investee_entity: @startup, investor: @investor, 
      funding_round: @funding_round)
    key_values(i, args)
    i = SaveInvestment.call(investment: i).investment
    puts "\n####Investment Created####\n"
    puts i.to_json
  end
end


Given('I should see my holdings in the holdings tab') do
  Investment.all.each do |inv|
    inv.holdings.each do |h|
      within("#holding_#{h.id}") do
        expect(page).to have_content(h.funding_round.name)
        expect(page).to have_content(h.holding_type)
        expect(page).to have_content(@investor.investor_name)
        expect(page).to have_content(h.investment_instrument)
        expect(page).to have_content(h.quantity)
        expect(page).to have_content(h.price)
        expect(page).to have_content(money_to_currency(h.value))
        expect(page).to have_content("Offer")
        
      end
    end
  end
end


Given('when I make an offer for my holdings') do
  h = Holding.first
  within("#holding_#{h.id}") do
    click_on("Offer")   
  end
  sleep(1)
  
  @new_offer = FactoryBot.build(:offer, holding_id: h.id, user_id:h.user_id, entity_id: h.entity_id,
    secondary_sale_id: @sale.id, investor_id: h.investor_id)
  @new_offer.quantity = @new_offer.allowed_quantity
  @offer = @new_offer

  steps %(
    Then when I submit the offer
  )
end

Then('I should see the offer') do
  h = Holding.first
  
  @offer = Offer.last

  @offer.user_id.should == @user.id
  @offer.secondary_sale_id.should == @sale.id
  @offer.entity_id.should == @startup.id
  @offer.quantity.should == @sale.percent_allowed * @offer.total_holdings_quantity / 100.0
  @offer.holding_id.should == h.id

  expect(page).to have_content(@user.full_name)
  expect(page).to have_content(@startup.name)
  expect(page).to have_content(@sale.name)
  expect(page).to have_content(@sale.percent_allowed)
  expect(page).to have_content(@offer.allowed_quantity / 100)
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

  @offer.approved = true
  @offer.save
end


Given('there are approved offers for the sale') do
  steps %(
    Given there are "3" exisiting investments "" from another firm in startups
  )
  Holding.all.each do |h|
    offer = FactoryBot.create(:offer, holding: h, entity: h.entity, secondary_sale: @sale, 
                          user: h.entity.employees.sample, investor: h.investor,
                          quantity: h.quantity * @sale.percent_allowed / 100, approved: true)
  end
end


Given('there are offers {string} for the sale') do |args|
  Holding.all.each do |h|
    offer = FactoryBot.build(:offer,holding: h, entity: h.entity, secondary_sale: @sale, 
                          user: h.entity.employees.sample, investor: h.investor)


    key_values(offer, args)
    saved = offer.save!    
    if saved
      key_values(offer, args)
      offer.save
      puts "\n####Offer Created####\n"
      puts offer.to_json                      
    end
  end
end


Given('there are {string} offers for the sale') do |approved_flag|
  steps %(
    Given there are "3" exisiting investments "" from another firm in startups
  )
  approved = approved_flag == "approved"
  Holding.all.each do |h|
    offer = Offer.create(holding: h, entity: h.entity, secondary_sale: @sale, 
                          user: h.entity.employees.sample, investor: h.investor,
                          quantity: h.quantity * @sale.percent_allowed / 100, approved: approved)


    offer.approved = approved
    offer.save    
    puts "\n####Offer Created####\n"
    puts offer.to_json                      
  end
end


Then('I should be able to create an interest in the sale') do
  visit(secondary_sale_path(@sale))
  click_on("New Interest")
  fill_in("interest_quantity", with: @sale.total_offered_quantity)
  fill_in("interest_price", with: @sale.min_price)
  click_on("Save")
  sleep(1)
end


Given('there are {string} interests {string} for the sale') do |count, args|

  @sale.reload

  (1..count.to_i).each do
    advisor_entity = FactoryBot.create(:entity, entity_type: "Advisor")
    user = FactoryBot.create(:user, entity: advisor_entity)

    interest = Interest.new(secondary_sale: @sale, 
                  user: user, 
                  quantity: @sale.total_offered_quantity, 
                  price: @sale.min_price,
                  short_listed: true)

    key_values(interest, args)
    saved = interest.save
    if saved
      puts "\n####Interest Created####\n"
      puts interest.to_json
    else
      puts "Interest not saved"
      puts interest.errors.full_messages
    end
  end

end

Then('when the allocation is done') do
  AllocationJob.perform_now(@sale.id)
  @sale.reload
  puts "\n####Sale Reloaded####\n"
  puts @sale.to_json
end

Then('the sale allocation percentage must be {string}') do |arg|
  puts "\n####Eligible Interests####\n"
  puts @sale.interests.eligible(@sale).to_json
  puts "\n####All Interests####\n"
  puts @sale.interests.to_json
  @sale.allocation_percentage.should == arg.to_f  
end


Then('the sale must be allocated correctly') do  
  @sale.total_offered_quantity.should == @sale.offers.approved.sum(:quantity)
  # @sale.total_offered_amount_cents.should == @sale.offers.approved.sum(:amount_cents)
  # @sale.total_interest_amount_cents.should == @sale.interests.short_listed.sum(:amount_cents)
  @sale.total_interest_quantity.should == @sale.interests.short_listed.sum(:quantity)
  @sale.offer_allocation_quantity.should == @sale.offers.approved.sum(:allocation_quantity)
  @sale.interest_allocation_quantity.should == @sale.interests.short_listed.sum(:allocation_quantity)
  @sale.allocation_interest_amount_cents.should == @sale.interests.short_listed.sum(:allocation_amount_cents) 
  
  @sale.allocation_offer_amount_cents.should == @sale.offers.approved.sum(:allocation_amount_cents)  
end


Then('the offers must be allocated correctly') do
  @sale.offers.approved.each do |offer|
    if @sale.allocation_percentage <= 1
      offer.allocation_percentage.should == @sale.allocation_percentage * 100
    else
      offer.allocation_percentage.should == 100.0
    end 
    # puts offer.to_json
    offer.allocation_quantity.should == (offer.quantity * offer.allocation_percentage / 100).ceil
  end
end

Then('the interests must be allocated correctly') do
  @sale.interests.short_listed.each do |interest|
    if @sale.allocation_percentage <= 1
      interest.allocation_percentage.should == 100.0
    else
      interest.allocation_percentage.should be_within(0.1).of(100.0 / @sale.allocation_percentage)
    end 
    puts interest.to_json
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
  investor_ids = Investor.not_holding.all.collect(&:id)
  Investment.where(investor_id: investor_ids).count.should == count.to_i
end

Then('the investor investments quantity should be the interest quantity') do
  investor_ids = Investor.not_holding.all.collect(&:id)
  Investment.where(investor_id: investor_ids).sum(:quantity).should == Interest.short_listed.escrow_deposited.sum(:quantity)
end


Then('the employee holdings must be reduced by the sold amount') do
  @holding_quantity = 0
  @sale.offers.approved.verified.each do |offer|
    offer.holding.quantity.should == offer.holding.orig_grant_quantity - offer.allocation_quantity
    @holding_quantity = @holding_quantity + offer.holding.quantity
  end
end

Then('the employee investments must be reduced by the sold amount') do
  Investment.where(employee_holdings: true).sum(:quantity).should == @holding_quantity
end
