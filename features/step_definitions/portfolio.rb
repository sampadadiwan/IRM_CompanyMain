include CurrencyHelper

  When('I create a new portfolio investment {string}') do |args|
    @new_portfolio_investment = PortfolioInvestment.new(fund: @fund)
    key_values(@new_portfolio_investment, args)

    visit(fund_path(@fund))
    sleep(1)
    click_on "Portfolio"    
    click_on "New Portfolio Investment"
    
    portfolio_company = @entity.investors.portfolio_companies.where(investor_name: @new_portfolio_investment.portfolio_company_name).first

    select(portfolio_company.investor_name, from: "portfolio_investment_portfolio_company_id")
    fill_in('portfolio_investment_amount', with: @new_portfolio_investment.amount)
    fill_in('portfolio_investment_quantity', with: @new_portfolio_investment.quantity)
    fill_in('portfolio_investment_investment_type', with: @new_portfolio_investment.investment_type)
    
    click_on "Save"    
    sleep(1)
  end
  
  Then('a portfolio investment should be created') do
    @portfolio_investment = PortfolioInvestment.last
    @portfolio_investment.quantity.should == @new_portfolio_investment.quantity
    @portfolio_investment.amount.should == @new_portfolio_investment.amount
    @portfolio_investment.investment_type.should == @new_portfolio_investment.investment_type
    @portfolio_investment.portfolio_company_name.should == @new_portfolio_investment.portfolio_company_name
  end

  Then('I should see the portfolio investment details on the details page') do
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@entity.name)
    expect(page).to have_content(@portfolio_investment.investment_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@portfolio_investment.portfolio_company_name)
    expect(page).to have_content(@portfolio_investment.quantity)
    expect(page).to have_content(@portfolio_investment.investment_type)
    expect(page).to have_content( money_to_currency @portfolio_investment.amount)
  end


  Given('there are {string} portfolio investments {string}') do |count, args|
    (1..count.to_i).each do |i|
      FactoryBot.create(:portfolio_investment, entity: @entity, fund: @fund)
    end
  end
  
  Then('an aggregate portfolio investment should be created') do
    @api = AggregatePortfolioInvestment.last
    @api.quantity.should == PortfolioInvestment.all.sum(:quantity)
    @api.bought_quantity.should == PortfolioInvestment.buys.sum(:quantity)
    @api.bought_amount_cents.should == PortfolioInvestment.buys.sum(:amount_cents)    
    @api.sold_quantity.should == PortfolioInvestment.sells.sum(:quantity)
    @api.sold_amount_cents.should == PortfolioInvestment.sells.sum(:amount_cents)
    @api.avg_cost_cents.round.should == (PortfolioInvestment.buys.sum(:amount_cents) / PortfolioInvestment.buys.sum(:quantity)).round(0)
    
  end
  
  Then('I should see the aggregate portfolio investment details on the details page') do
    visit(aggregate_portfolio_investment_path(@api))
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@api.portfolio_company_name)
    expect(page).to have_content(@api.quantity)
    expect(page).to have_content(@api.bought_quantity)
    expect(page).to have_content( money_to_currency @api.bought_amount)
    expect(page).to have_content(@api.sold_quantity)
    expect(page).to have_content( money_to_currency @api.sold_amount)
    expect(page).to have_content( money_to_currency @api.avg_cost)
  end


  

Given('there is a valuation {string} for the portfolio company') do |args|
  @portfolio_company = @entity.investors.portfolio_companies.last

  @valuation = FactoryBot.build(:valuation, entity: @entity, owner: @portfolio_company)
  key_values(@valuation, args)
  @valuation.save!
end

Then('the fmv must be calculated for the portfolio') do
  PortfolioInvestment.all.each do |pi|
    pi.fmv_cents.abs.should > 0
    pi.fmv_cents.should == (pi.quantity * @valuation.per_share_value_cents)
  end
end