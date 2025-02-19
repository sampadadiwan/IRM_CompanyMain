include CurrencyHelper

Given('I am at the investments page') do
  visit("/investments")
end

Given('I create an investment {string}') do |arg1|
  @funding_round ||= FundingRound.last.presence || FactoryBot.create(:funding_round, entity: @entity)
  @investment = FactoryBot.build(:investment, entity: @entity, category: "Lead Investor",
                      investment_type: @funding_round.name, funding_round: @funding_round)
  @investment.currency = @entity.currency
  key_values(@investment, arg1)
  @investment.investor ||= Investor.sample

  puts @investment.investor.to_json

  # click_on("New Investment")
  page.all(:link, "New Investment").last.click

  select(@investment.investor.investor_name, from: "investment_investor_id")
  select(@investment.funding_round.name, from: "investment_funding_round_id")
  select(@investment.investment_instrument, from: "investment_investment_instrument")
  select(@investment.category, from: "investment_category")


  fill_in('investment_quantity', with: @investment.quantity)
  fill_in('investment_price', with: @investment.price)
  fill_in('investment_liquidation_preference', with: @investment.liquidation_preference)
  fill_in('investment_spv', with: @investment.spv)
  fill_in('investment_investment_date', with: @investment.investment_date)

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
  fill_in('investment_investment_date', with: @investment.investment_date)

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
  expect(page).to have_content(number_with_delimiter(@investment.quantity))
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
  SaveInvestment.wtf?(investment: @investment)

  puts "\n####Investment####\n"
  puts @investment.errors.full_messages
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


Given('there is are {string} investors') do |count|
  (1..count.to_i).each do |i|
    vc = FactoryBot.create(:entity, entity_type: "Investor")
    inv = FactoryBot.create(:investor, entity: @entity, investor_entity: vc)
  end
end

Given('there are {string} investments {string}') do |count, args|
  (1..count.to_i).each do
    i = FactoryBot.build(:investment, entity: @entity, investor: Investor.sample,
      funding_round: @funding_round)
    key_values(i, args)

    # Hack to get the right funding round for Options
    if i.investment_instrument == "Options"
      i.funding_round = @option_pool.funding_round
    end

    SaveInvestment.wtf?(investment: i).success?.should == true
    puts "\n####Investment Created####\n"
    puts i.to_json
  end
end


############################################################################
############################################################################
#######################  Investor related test steps #############################
############################################################################
############################################################################


Given('there are {string} exisiting investments {string} from my firm in startups') do |count, args|
  @funding_round ||= FactoryBot.create(:funding_round, entity: @entity)

  (1..count.to_i).each do |i|
    @startup_entity = FactoryBot.create(:entity, entity_type: "Company")
    @startup_entity_employee = FactoryBot.create(:user, entity: @startup_entity)
    @investor = FactoryBot.create(:investor, investor_entity: @entity, entity: @startup_entity)
    (1..count.to_i).each do
      @investment = FactoryBot.build(:investment, entity:
          @startup_entity, investor: @investor, funding_round: @funding_round)

      SaveInvestment.wtf?(investment: @investment)
      ap @investment
    end
  end
end


Given('there are {string} exisiting investments {string} from another firm in startups') do |count, args|
  @funding_round ||= FactoryBot.create(:funding_round, entity: @entity)

  @another_entity = FactoryBot.create(:entity, entity_type: "Investor")
  @another_entity_employee = FactoryBot.create(:user, entity: @another_entity)

  Entity.startups.each do |company|
    @investor = FactoryBot.create(:investor, investor_entity: @another_entity, entity: company)
    (1..count.to_i).each do

      @investment = FactoryBot.build(:investment, entity: company,
                        investor: @investor, funding_round: @funding_round)
      SaveInvestment.wtf?(investment: @investment)
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
    InvestorAccess.create(investor:inv.investor, user: @user, first_name: @user.first_name,
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
      find("#action_#{entity.id}").click
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

      @investment = inv
      if @investment.investor_entity_id == @entity.id
        find("#action_#{entity.id}").click
        find("#investments_entity_#{entity.id}").click

        find("#show_investment_#{inv.id}").click
        steps %(
          Then I should see the investment details on the details page
        )
      else
        expect(page).to have_no_content(@investment.investor.investor_name)
      end
    end
    visit(investor_entities_entities_path)
  end
end

