
  include InvestmentsHelper
  include ActionView::Helpers::SanitizeHelper

  Given('I am at the investment_opportunities page') do
    visit(investment_opportunities_url)
  end
  
  When('I create a new investment_opportunity {string}') do |arg1|
    @investment_opportunity = FactoryBot.build(:investment_opportunity)
    key_values(@investment_opportunity, arg1)

    click_on("New Investment Opportunity")
    fill_in('investment_opportunity_company_name', with: @investment_opportunity.company_name)
    fill_in('investment_opportunity_fund_raise_amount', with: @investment_opportunity.fund_raise_amount)
    fill_in('investment_opportunity_min_ticket_size', with: @investment_opportunity.min_ticket_size)
    fill_in('investment_opportunity_last_date', with: @investment_opportunity.last_date)
    fill_in('investment_opportunity_currency', with: @investment_opportunity.currency)
    find('trix-editor').click.set(@investment_opportunity.details.to_plain_text)
    click_on("Save")
  end
  
  Then('an investment_opportunity should be created') do
    db_investment_opportunity = InvestmentOpportunity.last
    db_investment_opportunity.company_name.should == @investment_opportunity.company_name
    db_investment_opportunity.details.to_plain_text == @investment_opportunity.details.to_plain_text
    db_investment_opportunity.fund_raise_amount_cents.should == @investment_opportunity.fund_raise_amount_cents
    db_investment_opportunity.min_ticket_size_cents.should == @investment_opportunity.min_ticket_size_cents
    db_investment_opportunity.last_date.should == @investment_opportunity.last_date
    db_investment_opportunity.currency.should == @investment_opportunity.currency
    @investment_opportunity = db_investment_opportunity  end
  
  Then('I should see the investment_opportunity details on the details page') do
    visit(investment_opportunity_path(@investment_opportunity))
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount)
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size)
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@investment_opportunity.currency)
    expect(page).to have_content(@investment_opportunity.details.to_plain_text)
  end
  
  Then('I should see the investment_opportunity in all investment_opportunities page') do
    visit(investment_opportunities_path)
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount)
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size)
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))    
  end