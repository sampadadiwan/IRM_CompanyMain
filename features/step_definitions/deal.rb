include CurrencyHelper

Given('I am at the deals page') do
  visit("/deals")
end

When('I create a new deal {string}') do |arg1|
  @deal = FactoryBot.build(:deal)
  key_values(@deal, arg1)

  click_on("New Deal")
  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  select(@deal.status, from: "deal_status")
  click_on("Save")
end


When('I edit the deal {string}') do |arg1|
  key_values(@deal, arg1)

  click_on("Edit")

  fill_in('deal_name', with: @deal.name)
  fill_in('deal_amount', with: @deal.amount)
  select(@deal.status, from: "deal_status")

  click_on("Save")
  sleep(1)
end


Then('an deal should be created') do
  @created = Deal.last
  @created.name.should == @deal.name
  @created.amount.should == @deal.amount
  @created.status.should == @deal.status
  @deal = @created
end

Then('I should see the deal details on the details page') do
  visit(deal_path(@deal))
  find("#deal_tab").click()
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(money_to_currency(@deal.amount))
  expect(page).to have_content(@deal.status)
  # sleep(10)
end

Then('I should see the deal in all deals page') do
  visit("/deals")
  expect(page).to have_content(@deal.name)
  expect(page).to have_content(money_to_currency(@deal.amount))
  expect(page).to have_content(@deal.status)
end

Given('I visit the deal details page') do
  sleep(5)
  @deal.reload
  visit(deal_url(@deal))
end


Given('there exists a deal {string} for my company') do |arg1|
  @deal = FactoryBot.build(:deal)
  key_values(@deal, arg1)
  @deal = CreateDeal.call(deal: @deal).deal
  puts "\n####Deal####\n"
  puts @deal.to_json
end

Given('when I start the deal') do
  click_on("Start Deal")
  sleep(1) # To allow all deal activities to be created by sidekiq
end

Then('the deal should be started') do
  @deal.reload
  @deal.start_date.should_not == nil
  @deal.deal_activities.should_not == nil
end


Given('given there is a deal {string} for the entity') do |arg1|
  @deal = FactoryBot.build(:deal, entity_id: @entity.id)
  key_values(@deal, arg1)
  @deal = CreateDeal.call(deal: @deal).deal
  puts "\n####Deal####\n"
  puts @deal.to_json

end


Given('the deal is started') do
  @deal.start_deal
end

Given('I am {string} employee access to the deal') do |given|
  if given == "given" || given == "yes"
    @access_right = AccessRight.create(entity_id: @deal.entity_id, owner: @deal, user_id: @user.id)
  end
end

Given('I have {string} access to the deal') do |should|
  Pundit.policy(@user, @deal).show?.should == (should == "true")
end


Given('I should not have access to the deal') do
  Pundit.policy(@user, @deal).show?.should == false
end

Given('I have {string} access to the deal data room') do |arg|
  Pundit.policy(@user, @deal.data_room_folder).show?.to_s.should == arg
end

Then('another user {string} have access to the deal data room') do |arg|
  Pundit.policy(@another_user, @deal.data_room_folder).show?.to_s.should == arg
end

Given('another user {string} have access to the deal') do |arg|
  Pundit.policy(@another_user, @deal).show?.to_s.should == arg
end


Given('another entity is an investor {string} in entity') do |arg|
  random_pan = Faker::Alphanumeric.alphanumeric(number: 10, min_alpha: 3)
  @entity = Entity.find_or_initialize_by(name: "Another Entity 2", pan: random_pan)
  @investor = Investor.new(investor_name: @another_entity.name, investor_entity: @another_entity, entity: @entity, pan:random_pan)
  key_values(@investor, arg)
  @investor.save!
  puts "\n####Investor####\n"
  puts @investor.to_json
end

Given('another entity is a deal_investor {string} in the deal') do |arg|
  @deal_investor = DealInvestor.new(investor: @investor, entity: @entity, deal: @deal)
  key_values(@deal_investor, arg)
  @deal_investor.save!
  puts "\n####Deal Investor####\n"
  puts @deal_investor.to_json
end



Given('another user has investor access {string} in the investor') do |arg|
  @investor_access = InvestorAccess.new(entity: @entity, investor: @investor,
                            first_name: @another_user.first_name, last_name: @another_user.last_name,
                            email: @another_user.email, granter: @user )
  key_values(@investor_access, arg)

  @investor_access.save!
  puts "\n####Investor Access####\n"
  puts @investor_access.to_json
end


Given('investor has access right {string} in the deal') do |arg1|
  @access_right = AccessRight.new(owner: @deal, entity: @entity)
  key_values(@access_right, arg1)
  @access_right.save!
  puts "\n####Access Right####\n"
  puts @access_right.to_json
end



############################################################################
############################################################################
#######################  Investor related test steps #############################
############################################################################
############################################################################



Given('there are {string} exisiting deals {string} with another firm in the startups') do |count, args|
  @another_entity = FactoryBot.create(:entity, entity_type: "Investor")

  Entity.startups.each do |company|
    @investor = FactoryBot.create(:investor, investor_entity: @another_entity, entity: company)
    (1..count.to_i).each do
      deal = FactoryBot.build(:deal, entity: company)
      deal = CreateDeal.call(deal: deal).deal

      begin
        di = FactoryBot.create(:deal_investor, investor: @investor, entity: company, deal: deal)
      rescue Exception => e
        puts deal.entity.folders.collect(&:full_path)
        puts deal.to_json
        raise e
      end
    end
  end
end

Given('there are {string} exisiting deals {string} with my firm in the startups') do |count, args|

  Entity.startups.each do |company|
    (1..count.to_i).each do
      deal = FactoryBot.create(:deal, entity: company, name: Faker::Company.bs)
      puts "\n####Deal####\n"
      ap deal

      inv = deal.entity.investors.where(investor_name: @investor.investor_name).first
      di = FactoryBot.create(:deal_investor, investor: inv, entity: company, deal: deal)
      puts "\n####Deal Investor####\n"
      ap di    end
  end
end

Given('I am at the deal_investors page') do
  visit(deal_investors_path)
end

Then('I should not see the deals of the company') do
  DealInvestor.all.each do |di|
    within("#deal_investors") do
      expect(page).to have_no_content(di.deal_name)
      expect(page).to have_no_content(di.investor_name)
    end
  end
end


Then('I should see the deals of the company') do
  DealInvestor.where(investor_entity_id: @entity.id).each do |di|
    expect(page).to have_content(di.deal_name)
    expect(page).to have_content(di.investor_name)
  end
end


Given('I have access to all deals') do

  DealInvestor.where(investor_entity_id: @entity.id).all.each do |di|

    ia = InvestorAccess.create!(investor:di.investor, user: @user,
                          first_name: @user.first_name,
                          last_name: @user.last_name,
                          email: @user.email, approved: true,
                          entity_id: di.entity_id)

    ar = AccessRight.create(owner: di, access_type: "DealInvestor",
        entity: di.entity, access_to_investor_id: di.investor_id)

    puts "\n####Access Right####\n"
    puts ar.to_json
  end

  puts "\n####DealInvestor.for_investor####\n"
  puts DealInvestor.for_investor(@user).to_json
end

Given('the investors are added to the deal') do
  @user.entity.investors.not_holding.not_trust.each do |inv|
        ar = AccessRight.create( owner: @deal, access_type: "Deal",
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json
  end
end


Then('the deal data room should be setup') do
  @deal.reload
  puts "\n####Data Room####\n"
  puts @deal.data_room_folder.to_json
  @deal.data_room_folder.should_not == nil
  @deal.data_room_folder.name.should == "Data Room"
  @deal.data_room_folder.full_path.should == "/Deals/#{@deal.name}/Data Room"
end
