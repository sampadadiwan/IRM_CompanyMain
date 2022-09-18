
  When('a share transfer is done for quantity {string}') do |qty|
    @from_investment = Investment.first
    @orig_from_investment_qty = @from_investment.quantity

    @to_investor = Investor.last

    @share_transfer = ShareTransfer.new(entity_id: @entity.id, from_investor_id: @from_investment.investor_id, from_investment_id: @from_investment.id, to_investor_id: @to_investor.id, quantity: qty.to_i, price: 6000, transfer_date: Date.today, transfered_by_id: User.first.id)
        

    DoShareTransfer.call(share_transfer: @share_transfer)

  end
  
  Then('the share transfer must be created') do
    @to_investment = Investment.last
    
    @share_transfer.id.should_not == nil
    @share_transfer.entity_id.should == @entity.id
    
    @share_transfer.to_investment_id.should == @to_investment.id
    @share_transfer.to_investor_id.should == @to_investor.id

    @share_transfer.from_investment_id.should == @from_investment.id
    @share_transfer.from_investor_id.should == @from_investment.investor_id

  end
  
  Then('share transfer should result in a new investment') do
    @to_investment = Investment.last
    @to_investment.investor_id.should == @share_transfer.to_investor_id
    @to_investment.quantity.should == @share_transfer.quantity
    @to_investment.price_cents.should == @share_transfer.price * 100
    @to_investment.investment_date.should == @share_transfer.transfer_date
    
    @to_investment.investment_instrument.should == @from_investment.investment_instrument
    @to_investment.investment_type.should == @from_investment.investment_type
    @to_investment.category.should == @from_investment.category
    @to_investment.preferred_conversion.should == @from_investment.preferred_conversion
    @to_investment.currency.should == @from_investment.currency
    @to_investment.funding_round_id.should == @from_investment.funding_round_id
    
  end
  
  Then('the share transfer should result in the from investment quantity reduced') do
    @share_transfer.from_investment.quantity.should == @orig_from_investment_qty - @share_transfer.quantity
  end
  

  Then('share transfer should result in the aggregate investments being created') do
    from_agi = @entity.aggregate_investments.where(investor_id: @share_transfer.from_investor_id).first
    from_agi.send(@from_investment.investment_instrument.downcase.to_sym).should == @share_transfer.from_investment.quantity

    to_agi = @entity.aggregate_investments.where(investor_id: @share_transfer.to_investor_id).first
    to_agi.send(@to_investment.investment_instrument.downcase.to_sym).should == @share_transfer.to_investment.quantity
  end
  
  Then('share transfer should result in the holdings being created') do
    from_holding = @entity.holdings.where(investor_id: @share_transfer.from_investor_id).first
    from_holding.quantity.should == @share_transfer.from_investment.quantity

    to_holding = @entity.holdings.where(investor_id: @share_transfer.to_investor_id).first
    to_holding.quantity.should == @share_transfer.to_investment.quantity
  end
  