include InvestmentsHelper

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
end

Then('I should see the deal details on the details page') do
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
  visit(deal_url(@deal))
end


Given('there exists a deal {string} for my startup') do |arg1|
  @deal = FactoryBot.build(:deal)
  key_values(@deal, arg1)
  @deal = CreateDeal.call(deal: @deal).deal
  puts "\n####Deal####\n"
  puts @deal.to_json
end

Given('when I start the deal') do
  click_on("Start Deal")
  sleep(5) # To allow all deal activities to be created by sidekiq
end

Then('the deal should be started') do
  @deal.reload
  @deal.start_date.should_not == nil
  sleep(1)
  @deal.deal_activities.should_not == nil
end


Given('given there is a deal {string} for the entity') do |arg1|
  @deal = FactoryBot.build(:deal, entity_id: @entity.id)
  key_values(@deal, arg1)
  @deal = CreateDeal.call(deal: @deal).deal
  puts "\n####Deal####\n"
  puts @deal.to_json

end

Given('I should have access to the deal') do
  Pundit.policy(@user, @deal).show?.should == true
end


Given('I should not have access to the deal') do
  Pundit.policy(@user, @deal).show?.should == false
end

Given('another user {string} have access to the deal') do |arg|
  Pundit.policy(@another_user, @deal).show?.to_s.should == arg
end


Given('another entity is an investor {string} in entity') do |arg|
  @investor = Investor.new(investor_entity: @another_entity, entity: @entity)  
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
#######################  VC related test steps #############################  
############################################################################
############################################################################



Given('there are {string} exisiting deals {string} with another firm in the startups') do |count, args|
  @another_entity = FactoryBot.create(:entity, entity_type: "VC", name: "Another VC Firm")

  Entity.startups.each do |startup|
    @investor = FactoryBot.create(:investor, investor_entity: @another_entity, entity: startup)
    (1..count.to_i).each do 
      deal = FactoryBot.build(:deal, entity: startup)
      deal = CreateDeal.call(deal: deal).deal
      
      begin
        di = FactoryBot.create(:deal_investor, investor: @investor, entity: startup, deal: deal)
      rescue Exception => e
        puts deal.entity.folders.collect(&:full_path)  
        puts deal.to_json
        raise e
      end
    end 
  end
end

Given('there are {string} exisiting deals {string} with my firm in the startups') do |count, args|

  Entity.startups.each do |startup|
    (1..count.to_i).each do 
      deal = FactoryBot.create(:deal, entity: startup)
      di = FactoryBot.create(:deal_investor, investor: @investor, entity: startup, deal: deal)
    end
  end
end

Given('I am at the deal_investors page') do
  visit(deal_investors_path)
end

Then('I should not see the deals of the startup') do
  DealInvestor.all.each do |di|
    within("#deal_investors") do
      expect(page).to have_no_content(di.deal_name)
      expect(page).to have_no_content(di.investor_name)
    end
  end
end


Then('I should see the deals of the startup') do
  DealInvestor.all.each do |di|
    expect(page).to have_content(di.deal_name)
    expect(page).to have_content(di.investor_name)
  end
end


Given('I have access to all deals') do
  DealInvestor.all.each do |di|
    InvestorAccess.create!(investor:di.investor, user: @user, 
      first_name: @user.first_name, 
      last_name: @user.last_name,
      email: @user.email, approved: true, 
      entity_id: di.entity_id)

    AccessRight.create(owner: di.deal, access_type: "Deal",
        entity: di.entity, access_to_investor_id: di.investor_id)
  end
end
