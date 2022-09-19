
  When('a share transfer is done for quantity {string}') do |qty|
    
    @from_investment = Investment.first
    @orig_from_investment_qty = @from_investment.quantity
    @inital_funding_round = @from_investment.funding_round.dup

    @to_investor = Investor.last

    @share_transfer = ShareTransfer.new(entity_id: @entity.id, from_investor_id: @from_investment.investor_id, from_investment_id: @from_investment.id, to_investor_id: @to_investor.id, quantity: qty.to_i, price: 6000, transfer_date: Date.today, transfered_by_id: User.first.id)
        

    DoShareTransfer.call(share_transfer: @share_transfer)

  end
  
  Then('the share transfer must be created') do
    puts "\n####Share Transfer####\n"
    puts @share_transfer.to_json

    @to_investment = Investment.last
    
    @share_transfer.id.should_not == nil
    @share_transfer.entity_id.should == @entity.id
    
    @share_transfer.to_investment_id.should == @to_investment.id
    @share_transfer.to_investor_id.should == @to_investor.id

    @share_transfer.from_investment_id.should == @from_investment.id
    @share_transfer.from_investor_id.should == @from_investment.investor_id

  end

  Then('the holding transfer must be created') do
    puts "\n####Share Transfer####\n"
    puts @share_transfer.to_json

    @to_investment = Investment.last
    
    @share_transfer.id.should_not == nil
    @share_transfer.entity_id.should == @entity.id
    
    @share_transfer.to_investment_id.should == @to_investment.id
    @share_transfer.to_investor_id.should == @to_investor.id

    @share_transfer.from_holding_id.should == @from_holding.id
    @share_transfer.from_user_id.should == @from_holding.user_id

  end
  
  Then('share transfer should result in a new investment') do

    @to_investment = Investment.last
    puts "\n####To Investment####\n"
    puts @to_investment.to_json

    if @share_transfer.transfer_type == "Conversion"
      @to_investment.investor_id.should == @share_transfer.from_investor_id
      @to_investment.quantity.should == @share_transfer.quantity * @from_investment.preferred_conversion
      @to_investment.price_cents.should == (@from_investment.price_cents / @from_investment.preferred_conversion).round(0)
      @to_investment.investment_instrument.should == "Equity"
      @to_investment.preferred_conversion.should == 1
      @share_transfer.price.should == @to_investment.price_cents / 100
    else
      @to_investment.investor_id.should == @share_transfer.to_investor_id
      @to_investment.quantity.should == @share_transfer.quantity
      @to_investment.price_cents.should == @from_investment.price_cents
      @to_investment.investment_instrument.should == @from_investment.investment_instrument
      @to_investment.preferred_conversion.should == @from_investment.preferred_conversion
    end
    
    @to_investment.investment_date.should == @share_transfer.transfer_date    
    @to_investment.investment_type.should == @from_investment.investment_type
    @to_investment.category.should == @from_investment.category    
    @to_investment.currency.should == @from_investment.currency
    @to_investment.funding_round_id.should == @from_investment.funding_round_id
    
  end

  Then('holding transfer should result in a new investment') do

    @to_investment = Investment.last
    puts "\n####To Investment####\n"
    puts @to_investment.to_json

    if @share_transfer.transfer_type == "Conversion"
      @to_investment.investor_id.should == @share_transfer.from_investor_id
      @to_investment.quantity.should == @share_transfer.quantity * @from_investment.preferred_conversion
      @to_investment.price_cents.should == (@from_holding.price_cents / @from_holding.preferred_conversion).round(0)
      @to_investment.investment_instrument.should == "Equity"
      @to_investment.preferred_conversion.should == 1
      @share_transfer.price.should == @to_investment.price_cents / 100
    else
      @to_investment.investor_id.should == @share_transfer.to_investor_id
      @to_investment.quantity.should == @share_transfer.quantity
      @to_investment.price_cents.should == @from_holding.price_cents
      @to_investment.investment_instrument.should == @from_holding.investment_instrument
      @to_investment.preferred_conversion.should == @from_holding.preferred_conversion
    end
    
    @to_investment.investment_date.should == @share_transfer.transfer_date    
    @to_investment.investment_type.should == @from_holding.funding_round.name
    @to_investment.category.should == @to_investor.category    
    @to_investment.currency.should == @from_holding.entity.currency
    @to_investment.funding_round_id.should == @from_holding.funding_round_id
    
  end
  
  Then('the share transfer should result in the from investment quantity reduced') do
    puts "\n####From Investment####\n"
    puts @share_transfer.from_investment.to_json

    @share_transfer.from_investment.quantity.should == @orig_from_investment_qty - @share_transfer.quantity
  end
  

  Then('share transfer should result in the aggregate investments being created') do
    if @share_transfer.from_investor_id
      from_agi = @entity.aggregate_investments.where(investor_id: @share_transfer.from_investor_id).first
      from_agi.send(@from_investment.investment_instrument.downcase.to_sym).should == @share_transfer.from_investment.quantity
    end

    if @share_transfer.from_holding_id
      from_agi = @entity.aggregate_investments.where(investor_id: @share_transfer.from_holding.investor_id).first
      from_agi.send(@from_holding.investment_instrument.downcase.to_sym).should == @share_transfer.from_holding.quantity
    end

    
    if @share_transfer.to_investor_id
      to_agi = @entity.aggregate_investments.where(investor_id: @share_transfer.to_investor_id).first
      to_agi.send(@to_investment.investment_instrument.downcase.to_sym).should == @share_transfer.to_investment.quantity
    end
  end
  
  Then('share transfer should result in the holdings being created') do
    from_holding = @entity.holdings.where(investor_id: @share_transfer.from_investor_id).first
    from_holding.quantity.should == @share_transfer.from_investment.quantity

    to_holding = @entity.holdings.where(investor_id: @share_transfer.to_investor_id).last
    to_holding.quantity.should == @share_transfer.to_investment.quantity
  end
  
  Then('holding transfer should result in the holdings being created') do
    to_holding = @entity.holdings.where(investor_id: @share_transfer.to_investor_id).last
    to_holding.quantity.should == @share_transfer.to_investment.quantity
  end
  

When('a share conversion is done for quantity {string}') do |qty|
  @from_investment = Investment.first
  @orig_from_investment_qty = @from_investment.quantity
  @inital_funding_round = @from_investment.funding_round.dup

  @to_investor = Investor.last

  @share_transfer = ShareTransfer.new(entity_id: @entity.id, from_investor_id: @from_investment.investor_id, from_investment_id: @from_investment.id, to_investor_id: nil, quantity: qty.to_i, price: 6000, transfer_date: Date.today, transfered_by_id: User.first.id, transfer_type: "Conversion")
      

  DoShareTransfer.call(share_transfer: @share_transfer)
end

Then('share transfer should not effect the funding round') do
  @from_investment.funding_round.pre_money_valuation_cents.should == @inital_funding_round.pre_money_valuation_cents
  @from_investment.funding_round.post_money_valuation_cents.should == @inital_funding_round.post_money_valuation_cents
  @from_investment.funding_round.amount_raised_cents.should == @inital_funding_round.amount_raised_cents
end

Then('holding transfer should not effect the funding round') do
  @from_holding.funding_round.pre_money_valuation_cents.should == @inital_funding_round.pre_money_valuation_cents
  @from_holding.funding_round.post_money_valuation_cents.should == @inital_funding_round.post_money_valuation_cents
  @from_holding.funding_round.amount_raised_cents.should == @inital_funding_round.amount_raised_cents
end


When('a share transfer is done from the employee to the investor for quantity {string}') do |qty|
  @from_holding = @holdings_investor.holdings.first
  puts "\n####From Holding####\n"
  puts @from_holding.to_json

  @orig_from_holding_qty = @from_holding.quantity
  @inital_funding_round = @from_holding.funding_round.dup

  @to_investor = Investor.last

  @share_transfer = ShareTransfer.new(entity_id: @entity.id, from_holding: @from_holding, to_investor_id: @to_investor.id, quantity: qty.to_i, price: 6000, transfer_date: Date.today, transfered_by_id: User.first.id)
      

  DoHoldingTransfer.call(share_transfer: @share_transfer)
end

Then('the holding transfer should result in the from holding quantity reduced') do
  @share_transfer.from_holding.reload
  @share_transfer.from_holding.quantity.should == @orig_from_holding_qty - @share_transfer.quantity
end
