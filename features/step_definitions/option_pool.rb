  include InvestmentsHelper

  Given('I am at the Option Pools page') do
    visit(option_pools_path)
  end
  
  When('I create a new esop pool {string}') do |args|
    @option_pool = FactoryBot.build(:option_pool)
    @option_pool.entity = @user.entity

    key_values(@option_pool, args)

    click_on("New Option Pool")
    
    fill_in('option_pool_name', with: @option_pool.name)
    fill_in('option_pool_start_date', with: @option_pool.start_date)
    fill_in('option_pool_number_of_options', with: @option_pool.number_of_options)
    fill_in('option_pool_excercise_price', with: @option_pool.excercise_price)
    fill_in('option_pool_excercise_period_months', with: @option_pool.excercise_period_months)
    click_on("Next")
    click_on("Next")
    
    click_on("Save")
  end
  
  Then('an esop pool should be created') do
    @created = OptionPool.last
    @created.name.should == @option_pool.name
    @created.number_of_options.should == @option_pool.number_of_options
    @created.excercise_price.should == @option_pool.excercise_price
    @created.excercise_period_months.should == @option_pool.excercise_period_months
    @created.start_date.should == @option_pool.start_date    
  end
  

Then('the trust company must have the investment') do
  puts "\n####Trust Company####\n"
  puts @created.entity.trust_investor.to_json
  puts "\n####Trust Company Investments####\n"
  puts @created.entity.trust_investor.investments.to_json

  @trust_investment = @created.entity.trust_investor.investments.first
  @trust_investment.should_not be_nil
  @trust_investment.quantity.should == @created.trust_quantity
end

Then('the trust company must have no investment') do
  @trust_investment = @created.entity.trust_investor.investments.first
  @trust_investment.should be_nil
end

Then('when I approve the esop pool in the UI') do
  visit(option_pool_path(@created))
  click_on("Approve")
  click_on("Proceed")  
  sleep(1)
end



  Then('I should see the esop pool details on the details page') do
    # click_on("Details")
    expect(page).to have_content(@option_pool.name)
    expect(page).to have_content(custom_format_number @option_pool.number_of_options)
    expect(page).to have_content(@option_pool.excercise_period_months)
    expect(page).to have_content(@option_pool.start_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(money_to_currency @option_pool.excercise_price)
  end
  
  Then('I should see the esop pool in all esop pools page') do
    visit(option_pools_path)
    expect(page).to have_content(@option_pool.name)
    expect(page).to have_content(@option_pool.number_of_options)
    expect(page).to have_content(@option_pool.excercise_period_months)
    expect(page).to have_content(@option_pool.start_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(money_to_currency @option_pool.excercise_price)
  end
  

  Given('a esop pool {string} is created with vesting schedule {string}') do |args, schedule_args|
    @option_pool = FactoryBot.build(:option_pool)
    @option_pool.entity = @user.entity
    key_values(@option_pool, args)

    schedule_args.split(",").each do |arg|
      v = VestingSchedule.new(months_from_grant: arg.split(":")[0], vesting_percent: arg.split(":")[1])
      @option_pool.vesting_schedules << v
    end

    @option_pool = CreateOptionPool.call(option_pool: @option_pool).option_pool
    if @option_pool.approved 
      @option_pool = ApproveOptionPool.call(option_pool: @option_pool).option_pool
    end

    puts "\n####Created Option Pool####\n"
    puts @option_pool.to_json(include: :vesting_schedules)

  end
  
  Then('the vesting schedule must also be created') do
    @created = OptionPool.last
    puts "\n####Vesting Schedule####\n"
    puts @option_pool.vesting_schedules.to_json

    @created.vesting_schedules.count.should_not == 0 
  end


  Then('the corresponding funding round is created for the pool') do
    @funding_round = FundingRound.last
    @option_pool.funding_round_id.should == @funding_round.id
    @funding_round.name.should == @option_pool.name
    @funding_round.entity_id.should == @option_pool.entity_id    
  end
  
  Then('an esop pool should not be created') do
    OptionPool.count.should == 0
  end
  
  Then('the pool granted amount should be {string}') do |arg|
    @option_pool.reload
    puts @option_pool.to_json
    @option_pool.allocated_quantity.should == arg.to_f
  end
  
  Given('the option grant date is {string} ago') do |months|
    @holding = Holding.last
    @holding.grant_date = Date.today - months.to_i.months - 1.day
    @holding.save!
    VestedJob.new.perform
    @holding.reload
  end
  
  Then('the vested amount should be {string}') do |qty|
    @holding.reload
    @option_pool.reload
    puts "@option_pool.vested_quantity: #{@option_pool.vested_quantity}, @holding.vested_quantity: #{@holding.vested_quantity}"
    @holding.vested_quantity.should == qty.to_f
    @option_pool.vested_quantity.should == qty.to_f
  end


Then('the lapsed amount should be {string}') do |qty|
  VestedJob.new.perform
  @option_pool.reload
  puts "@option_pool.lapsed_quantity: #{@option_pool.lapsed_quantity}"
  @option_pool.lapsed_quantity.should == qty.to_f
  @holding.reload
  @holding.lapsed_quantity.should == qty.to_f
end

Then('the unexcercised amount should be {string}') do |qty|
  puts "@option_pool.net_avail_to_excercise_quantity: #{@option_pool.net_avail_to_excercise_quantity}"
  @holding.net_avail_to_excercise_quantity.should == qty.to_f
  @option_pool.net_avail_to_excercise_quantity.should == qty.to_f
end

Given('the option is cancelled {string}') do |arg|
  CancelHolding.call(holding: @holding, all_or_unvested: arg)
end


Then('when the option is excercised {string}') do |args|
  @holding.reload
  puts @holding.to_json

  @excercise = Excercise.new(entity_id: @holding.entity_id, holding_id: @holding.id, quantity: @holding.vested_quantity, option_pool_id: @option_pool.id, user_id: @holding.user.id, price_cents: @option_pool.excercise_price_cents, amount: @option_pool.excercise_price_cents * @holding.vested_quantity)

  key_values(@excercise, args)
  @excercise.save!

  puts "\n####Excercise####\n"
  puts @excercise.to_json

end

Then('the excercise is approved') do
  @excercise = ApproveExcercise.call(excercise: @excercise).excercise
  @excercise.reload
end

Then('the unvested amount should be {string}') do |arg|
  @option_pool.net_unvested_quantity.should == arg.to_f
end

Then('the option pool must have {string}') do |args|
  pool = Hash.new
  key_values(pool, args)
  
  @option_pool.reload
  
  puts "@option_pool.net_avail_to_excercise_quantity #{@option_pool.net_avail_to_excercise_quantity}"
  puts "@option_pool.lapsed_quantity #{@option_pool.lapsed_quantity}"
  puts "@option_pool.excercised_quantity #{@option_pool.excercised_quantity}"
  ap @option_pool

  @option_pool.vested_quantity.should == pool["vested_quantity"].to_i
  @option_pool.lapsed_quantity.should == pool["lapsed_quantity"].to_i
  @option_pool.excercised_quantity.should == pool["excercised_quantity"].to_i
  @option_pool.net_avail_to_excercise_quantity.should == pool["net_avail_to_excercise_quantity"].to_i
  @option_pool.net_unvested_quantity.should == pool["net_unvested_quantity"].to_i
  @option_pool.allocated_quantity.should == pool["allocated_quantity"].to_i

end

Then('the option holding must have {string}') do |args|
  holding = Hash.new
  key_values(holding, args)
  
  @holding.reload
  puts "@holding.net_avail_to_excercise_quantity #{@holding.net_avail_to_excercise_quantity}"
  puts "@holding.lapsed_quantity #{@holding.lapsed_quantity}"
  puts "@holding.excercised_quantity #{@holding.excercised_quantity}"
  puts "@holding.uncancelled_quantity #{@holding.uncancelled_quantity}"
  ap @holding

  @holding.vested_quantity.should == holding["vested_quantity"].to_i
  @holding.lapsed_quantity.should == holding["lapsed_quantity"].to_i
  @holding.excercised_quantity.should == holding["excercised_quantity"].to_i
  @holding.net_avail_to_excercise_quantity.should == holding["net_avail_to_excercise_quantity"].to_i
  @holding.net_unvested_quantity.should == holding["net_unvested_quantity"].to_i
  @holding.quantity.should == holding["quantity"].to_i

end

Then('the trust esop holdings must be reduced by {string}') do |arg|
  trust_investor = @holding.entity.trust_investor
  @trust_holding = trust_investor.holdings.where(option_pool_id: @option_pool.id, 
                                  investment_instrument: "Options").first

  # ap trust_investor.holdings
  @trust_holding.quantity.should == @option_pool.number_of_options - arg.to_i
end



Then('the excercise must be created') do
  
end

Then('the esop pool must be updated with the excercised amount') do
  puts @holding.reload.to_json
  puts @option_pool.reload.to_json
  @option_pool.excercised_quantity.should == @excercise.quantity
end

Then('the option holding must be updated with the excercised amount') do
  @holding.reload
  @holding.excercised_quantity.should == @excercise.quantity
  @holding.quantity.should == @holding.orig_grant_quantity - @excercise.quantity 
end

  
Then('the investment total quantity must be {string}') do |args|
  # ap Investment.all
  Investment.all.sum(:quantity).should == args.to_i
end

Then('the new investment and holding must be created with excercised quantity') do
  
  @new_holding = Holding.last
  puts "\n####New Holding####\n"
  puts @new_holding.to_json
  @new_holding.quantity.should == @excercise.quantity
  @new_holding.entity_id.should == @excercise.entity_id
  @new_holding.user_id.should == @excercise.user_id
  @new_holding.investment_instrument.should == "Equity"
  
  @new_investment = @new_holding.investment
  puts "\n####New Investment####\n"
  puts @new_investment.to_json

  @new_investment.quantity.should == @excercise.quantity
  @new_investment.investee_entity_id.should == @excercise.entity_id
  @new_investment.investment_instrument.should == "Equity"
  
end
  