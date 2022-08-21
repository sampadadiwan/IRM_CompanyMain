include InvestmentsHelper

Given('I am at the investments page') do
  visit("/investments")
end

Given('I create an investment {string}') do |arg1|
  @funding_round ||= FundingRound.last.presence || FactoryBot.create(:funding_round, entity: @entity)
  @investment = FactoryBot.build(:investment, entity: @entity, 
                      investment_type: @funding_round.name, funding_round: @funding_round)
  @investment.currency = @entity.currency
  key_values(@investment, arg1)
  @investment.investor ||= Investor.not_holding.sample

  puts @investment.investor.to_json
  
  click_on("New Investment")

  select(@investment.investor.investor_name, from: "investment_investor_id")
  select(@investment.category, from: "investment_category")
  select(@investment.funding_round.name, from: "investment_funding_round_id")
  select(@investment.investment_instrument, from: "investment_investment_instrument")

  fill_in('investment_quantity', with: @investment.quantity)
  fill_in('investment_price', with: @investment.price)
  fill_in('investment_liquidation_preference', with: @investment.liquidation_preference)
  fill_in('investment_spv', with: @investment.spv)
  fill_in('investment_investment_date', with: @investment.investment_date.strftime("%d/%m/%Y"))

  sleep(1)
  click_on("Save")
end


Then('when I edit the investment {string}') do |arg1|
  visit(investment_path(@investment))
  click_on("Edit")
  @edit_investment = @investment
  key_values(@edit_investment, arg1)

  select(@edit_investment.category, from: "investment_category")
  select(@edit_investment.investment_type, from: "investment_funding_round_id")
  select(@edit_investment.investment_instrument, from: "investment_investment_instrument")
  
  fill_in('investment_quantity', with: @edit_investment.quantity)
  fill_in('investment_price', with: @edit_investment.price)
  fill_in('investment_liquidation_preference', with: @investment.liquidation_preference)
  fill_in('investment_spv', with: @investment.spv)
  fill_in('investment_investment_date', with: @investment.investment_date.strftime("%d/%m/%Y"))

  click_on("Save")
  sleep(1)
  @investment = Investment.last
  
end

Then('an investment should be created') do
  @created = Investment.last
  puts "\n####Investment Created####\n"
  puts @created.to_json

  @created.investor_id.should == @investment.investor_id
  @created.category.should == @investment.category
  @created.investment_type.should == @investment.investment_type
  @created.investment_instrument.should == @investment.investment_instrument
  @created.quantity.should == @investment.quantity
  @created.price_cents.should == @investment.price_cents
  @created.currency.should == @investment.entity.currency
  @created.amount.should == @investment.price * @investment.quantity 
  @created.liquidation_preference.should == @investment.liquidation_preference 
  @created.spv.should == @investment.spv
  
  @investment = @created
end

Then('I should see the investment details on the details page') do
  visit(investment_path(@investment))
  steps %(
    Then I should see the investment details    
  )
  expect(page).to have_content(money_to_currency(@investment.amount))
end

Then('I should see the investment in all investments page') do
  visit("/investments")
  steps %(
    Then I should see the investment details    
  )
end

Then('I should see the investment details') do
  expect(page).to have_content(@investment.investor.investor_name)
  expect(page).to have_content(@investment.category)
  expect(page).to have_content(@investment.investment_instrument)
  expect(page).to have_content(@investment.investment_type)
  expect(page).to have_content(@investment.quantity)
  expect(page).to have_content(money_to_currency(@investment.price))
end

Given('given there is a investment {string} for the entity') do |arg1|

  @funding_round ||= FactoryBot.create(:funding_round, entity: @entity)
  @investment = FactoryBot.build(:investment, investor: @investor, 
                                  entity: @entity, 
                                  funding_round: @funding_round,
                                  investment_instrument: Investment::EQUITY_LIKE[rand(3)])
  @investment.currency = @entity.currency
  key_values(@investment, arg1)
  @investment = SaveInvestment.call(investment: @investment).investment

  puts "\n####Investment####\n"
  puts @investment.to_json
end

Given('I should have access to the investment') do
  Pundit.policy(@user, @investment).show?.should == true
end


Given('I should have access to the aggregate_investment') do
  Pundit.policy(@user, @investment.aggregate_investment).show?.should == true
end


Given('another user has {string} access to the investment') do |arg|
  Pundit.policy(@another_user, @investment).show?.to_s.should == arg
end

Then('another user has {string} access to the aggregate_investment') do |arg|
  Pundit.policy(@another_user, @investment.aggregate_investment).show?.to_s.should == arg
end


Given('investor has access right {string} in the investment') do |arg1|
  @access_right = AccessRight.new(owner: @entity, entity: @entity)
  key_values(@access_right, arg1)
  
  @access_right.save
  puts "\n####Access Right####\n"
  puts @access_right.to_json
end


Then('a holding should be created for the investor') do
  sleep(1)
  @holding = @investment.holdings.last
  puts "\n####Holding####\n"
  puts @holding.to_json

  @holding.quantity.should == @investment.quantity
  @holding.investment_instrument.should == @investment.investment_instrument
  @holding.entity_id.should == @investment.entity_id  
  @holding.investor_id.should == @investment.investor_id
  @holding.user_id.should == nil
  @holding.holding_type.should == "Investor"

  @investment.holdings.count.should == 1
end



Given('there are {string} employee investors') do |arg|
  @holdings_investor = @entity.investors.where(is_holdings_entity: true).first
  @investor_entity = @holdings_investor.investor_entity
  (0..arg.to_i-1).each do
    user = FactoryBot.create(:user, entity: @investor_entity)
    ia = InvestorAccess.create!(investor:@holdings_investor, user: user, email: user.email, 
        first_name: user.first_name, last_name: user.last_name, 
        approved: true, entity_id: @holdings_investor.entity_id)

    puts "\n####InvestorAccess####\n"
    puts ia.to_json
  end
end

Given('Given I create a holding for each employee with quantity {string}') do |arg|
  @holding_orig_grant_quantity = arg.to_i
  @entity.investor_accesses.each do |emp|
    visit(investor_url(@holdings_investor))
    click_on("Employee Investors")
    find("#investor_access_#{emp.id}").click_link("Add Holding")
    fill_in('holding_orig_grant_quantity', with: @holding_orig_grant_quantity)
    fill_in('holding_price', with: 1000*emp.user_id)
    select("Equity", from: "holding_investment_instrument")
    select(@funding_round.name, from: "holding_funding_round_id")
    # select("Employee", from: "holding_holding_type")

    click_on("Save")
    sleep(1)
  end
end

Then('There should be a corresponding holdings created for each employee') do

  puts Holding.all.to_json
    
  @investor_entity.employees.each do |emp|
    emp.holdings.count.should == 1
    holding = emp.holdings.first
    holding.orig_grant_quantity.should == @holding_orig_grant_quantity
    holding.quantity.should == @holding_orig_grant_quantity
    holding.price_cents.should == 1000 * 100 * emp.id    
    holding.value_cents.should == @holding_orig_grant_quantity * 1000 * 100 * emp.id
    holding.holding_type.should == "Employee"
    holding.entity_id.should == @entity.id
    holding.investment_instrument.should == "Equity"
  end
end

Then('There should be a corresponding investment created') do
  @holding_investment = Investment.last
  @holding_investment.entity_id.should == @entity.id
  @holding_investment.investor_entity_id.should == @investor_entity.id
  @holding_investment.investment_instrument.should == "Equity"
  @holding_investment.quantity.should == Holding.all.sum(:quantity)
  @holding_investment.category.should == "Employee"
  @holding_investment.investment_type.should == @funding_round.name
  @holding_investment.funding_round.id.should == @funding_round.id
end

Then('when the holdings are approved') do
  Holding.all.each do |h|
    ApproveHolding.call(holding: h)
  end
end


Then('Investments is updated with the holdings') do
  #ap Investment.all
  Holding.not_investors.each do |h|
    h.investment.quantity.should ==  h.investment.holdings.sum(:quantity)
    h.investment.amount_cents.should ==  h.investment.holdings.sum(:value_cents)
    h.investment.price_cents.should == h.investment.holdings.sum(:value_cents) / h.investment.holdings.sum(:quantity)
  end
end

Given('there is a FundingRound {string}') do |args|
  @funding_round = FactoryBot.build(:funding_round, entity: @entity)
  key_values(@funding_round, args)
  @funding_round.save
end


Then('the funding round must be updated with the investment') do
  sleep(2) #Allow job to run
  @funding_round ||= FundingRound.last
  puts @funding_round.reload.to_json
  @funding_round.amount_raised_cents.should == @funding_round.investments.all.sum(:amount_cents)
  @funding_round.equity.should == @funding_round.investments.equity.sum(:quantity)
  @funding_round.preferred.should == @funding_round.investments.preferred.sum(:quantity)
  @funding_round.options.should == @funding_round.investments.options.sum(:quantity)
end


Given('the funding rounds must be updated with the right investment') do
  FundingRound.all.each do |funding_round|
    puts funding_round.to_json
    funding_round.amount_raised_cents.should == funding_round.investments.sum(:amount_cents)
    funding_round.equity.should == funding_round.investments.equity.sum(:quantity)
    funding_round.preferred.should == funding_round.investments.preferred.sum(:quantity)
    funding_round.options.should == funding_round.investments.options.sum(:quantity)
  end
end


Then('the entity must be updated with the investment') do
  puts @entity.reload.to_json
  @entity.equity.should == Investment.equity.sum(:quantity)
  @entity.preferred.should == Investment.preferred.sum(:quantity)
  @entity.options.should == Investment.options.sum(:quantity)
  @entity.total_investments.should == Investment.sum(:amount_cents)
  @entity.investments_count.should == Investment.count
end


Given('there is are {string} investors') do |count|
  (1..count.to_i).each do |i|
    vc = FactoryBot.create(:entity, entity_type: "VC")
    inv = FactoryBot.create(:investor, entity: @entity, investor_entity: vc)
  end
end

Given('there are {string} investments {string}') do |count, args|
  (1..count.to_i).each do 
    i = FactoryBot.build(:investment, entity: @entity, investor: Investor.not_holding.sample, 
      funding_round: @funding_round)
    key_values(i, args)

    # Hack to get the right funding round for Options
    if i.investment_instrument == "Options"
      i.funding_round = @option_pool.funding_round
    end
    
    i = SaveInvestment.call(investment: i).investment
    puts "\n####Investment Created####\n"
    puts i.to_json
  end
end


Given('the aggregate investments must be created') do
  AggregateInvestment.all.each do |agg|
    puts "\n####AggregateInvestment####\n"
    puts agg.to_json
    
    agg.entity_id.should == @entity.id
    investments = Investment.where(investor_id: agg.investor_id, 
                                   entity_id: agg.entity_id)
    agg.equity.should == investments.equity.sum(:quantity)
    agg.preferred.should == investments.preferred.sum(:quantity)
    agg.options.should == investments.options.sum(:quantity)

    
  end
end

Given('the percentage must be computed correctly') do
  InvestmentPercentageHoldingJob.new.perform(Investment.first.id)
  Investment.sum(:percentage_holding).should be_within(0.1).of(100)
  Investment.sum(:diluted_percentage).should be_within(0.1).of(100)
  AggregateInvestment.sum(:percentage).should be_within(0.1).of(100)
  AggregateInvestment.sum(:full_diluted_percentage).should be_within(0.1).of(100)
end



Then('when I see the aggregated investments') do
  sleep(1)
  visit(aggregate_investments_path)
end

Then('I must see one {string} aggregated investment for the investor') do |args|
  AggregateInvestment.where(investor_id: @investor.id).count.should == args.to_i
end

Then('I must see the aggregated investment with {string}') do |args|
  @aggregate_investment = AggregateInvestment.last
  kv = {}
  key_values(kv, args)
  puts kv
  within("#aggregate_investment_#{@aggregate_investment.id}") do
    within(".equity") do
      expect(page).to have_content(kv["Equity"])
    end
    within(".preferred") do
      expect(page).to have_content(kv["Preferred"])
    end
    within(".options") do
      expect(page).to have_content(kv["Options"])
    end
  end
end



############################################################################
############################################################################
#######################  VC related test steps #############################  
############################################################################
############################################################################


Given('there are {string} exisiting investments {string} from my firm in startups') do |count, args|
  @funding_round ||= FactoryBot.create(:funding_round, entity: @entity)

  (1..count.to_i).each do |i|
    @startup_entity = FactoryBot.create(:entity, entity_type: "Startup", name: "Startup #{i}")
    @startup_entity_employee = FactoryBot.create(:user, entity: @startup_entity)
    @investor = FactoryBot.create(:investor, investor_entity: @entity, entity: @startup_entity)
    (1..count.to_i).each do 
      @investment = FactoryBot.build(:investment, entity: 
          @startup_entity, investor: @investor, funding_round: @funding_round)

      @investment = SaveInvestment.call(investment: @investment).investment
    end
  end
end


Given('there are {string} exisiting investments {string} from another firm in startups') do |count, args|
  @funding_round ||= FactoryBot.create(:funding_round, entity: @entity)

  @another_entity = FactoryBot.create(:entity, entity_type: "VC", name: "Another VC Firm")
  @another_entity_employee = FactoryBot.create(:user, entity: @another_entity)

  Entity.startups.each do |startup|
    @investor = FactoryBot.create(:investor, investor_entity: @another_entity, entity: startup)
    (1..count.to_i).each do 
      @investment = FactoryBot.build(:investment, entity: startup, 
                        investor: @investor, funding_round: @funding_round)
      @investment = SaveInvestment.call(investment: @investment).investment
    end
  end
end


Given('I am at the investor_entities page') do
  visit(investor_entities_entities_path)
end

Then('I should see the entities I have invested in') do
  @entity.investments.each do |inv|
    expect(page).to have_content(inv.entity.name)
  end
end

Then('I should not see the entities I have invested in') do
  @entity.investments.each do |inv|
    expect(page).to have_no_content(inv.entity.name)
  end
end

Given('I have been granted access {string} to the investments') do |arg|
  Investment.joins(:investor).where("investors.investor_entity_id=?", @entity.id).each do |inv|
    InvestorAccess.create!(investor:inv.investor, user: @user, first_name: @user.first_name,
        last_name: @user.last_name, email: @user.email, approved: true, 
        entity_id: inv.entity_id)

    AccessRight.create(owner: inv.entity, access_type: "Investment", metadata: arg,
        entity: inv.entity, access_to_investor_id: inv.investor_id)
  end

end


Then('I should be able to see the investments for each entity') do
  Entity.for_investor(@user).each do |entity|
    entity.investments.joins(:investor).where("investors.investor_entity_id": @user.entity_id).each do |inv|  
      visit(investor_entities_entities_path)
      sleep(1)
      find("#investments_entity_#{entity.id}").click
      @investment = inv
      find("#show_investment_#{inv.id}").click  
      steps %(
        Then I should see the investment details on the details page    
      )
    end  
    visit(investor_entities_entities_path)    
  end
end


Then('I should be able to see only my investments for each entity') do
  Entity.startups.each do |entity|
    entity.investments.each do |inv|
      visit(investor_entities_entities_path)
      find("#investments_entity_#{entity.id}").click
      click_on("Details View")

      @investment = inv
      if @investment.investor_entity_id == @entity.id
      steps %(
        Then I should see the investment details   
        Then I should see the investment details on the details page    
      )
      else
        expect(page).to have_no_content(@investment.investor.investor_name)
      end
    end  
    visit(investor_entities_entities_path)    
  end
end



Given('Given I upload a holdings file') do
  Sidekiq.redis(&:flushdb)

  @existing_user_count = User.count
  visit("/holdings")
  click_on("Upload Holdings")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('import_upload_import_file', File.absolute_path('./public/sample_uploads/holdings.xlsx'))
  click_on("Save")
  sleep(10)
end

Then('There should be {string} holdings created') do |count|
  (Holding.not_investors.count).should == count.to_i
  
  Holding.employees.all.sum(:quantity).should == 1400
  Holding.founders.all.sum(:quantity).should == 300

  Holding.not_investors.all.each do |h|
    h.investor.category.should == h.holding_type
    h.user.entity_id.should == h.investor.investor_entity_id
  end
  
end

Then('There should be {string} users created for the holdings') do |count|
  (User.count - @existing_user_count).should == count.to_i
end

Then('There should be {string} Investments created for the holdings') do |count|
  Investment.joins(:investor).where("investors.is_holdings_entity=?", true).count.should == count.to_i  
end
