
  include CurrencyHelper
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
    find(".show_details_link").click
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount)
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size)
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@investment_opportunity.currency)
    expect(page).to have_content(@investment_opportunity.details.to_plain_text)
  end
  
  Then('I should see the investment_opportunity in all investment_opportunities page') do
    visit(investment_opportunities_path)
    force_units = @investment_opportunity.default_currency_units
    expect(page).to have_content(@investment_opportunity.company_name)
    expect(page).to have_content(money_to_currency @investment_opportunity.fund_raise_amount, {force_units: })

    if force_units == "Crores" && @investment_opportunity.min_ticket_size.to_d < 100_00000
      # If committed_amount is less than a crore, then show in lakhs
      force_units = "Lakhs"
    end
    expect(page).to have_content(money_to_currency @investment_opportunity.min_ticket_size, {force_units:})
    expect(page).to have_content(@investment_opportunity.last_date.strftime("%d/%m/%Y"))    
  end


  Given('there is an investment_opportunity {string}') do |arg1|
    @investment_opportunity = FactoryBot.build(:investment_opportunity, entity: @entity)
    key_values(@investment_opportunity, arg1)
    @investment_opportunity.save!

    puts "\n####InvestmentOpportunity####\n"
    puts @investment_opportunity.to_json
  end
  
  Given('the investors are added to the investment_opportunity') do
    @user.entity.investors.not_holding.not_trust.each do |inv|
        ar = AccessRight.create!( owner: @investment_opportunity, access_type: "InvestmentOpportunity", 
                                 access_to_investor_id: inv.id, entity: @user.entity)


        puts "\n####Granted Access####\n"
        puts ar.to_json                            
    end 
    
  end
  
  When('I upload a document for the investment_opportunity') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Actions"
    click_on "New Document"
    fill_in('document_name', with: "Test IO Doc")
    # select("Document", from: "document_tag_list")    
    attach_file('files[]', File.absolute_path('./public/sample_uploads/investor_access.xlsx'), make_visible: true)
    sleep(2)
    check('Send email', allow_label_click: true)
    click_on("Save")
    sleep(2)
  end
  
  Then('The document must be created with the owner set to the investment_opportunity') do
    @document = Document.last
    puts "\n####Uploaded Doc####\n"
    puts @document.to_json                            
    @investment_opportunity.reload
    @investment_opportunity.documents.first.should == @document
  end
  
  

  When('I create an EOI {string}') do |arg1|
    @expression_of_interest = FactoryBot.build(:expression_of_interest)
    key_values(@expression_of_interest, arg1)
    
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    click_on "New Interest"
    fill_in('expression_of_interest_amount', with: @expression_of_interest.amount.to_i)
    select(@expression_of_interest.investor.investor_name, from: "expression_of_interest_investor_id")
    find('trix-editor').click.set(@expression_of_interest.details.to_plain_text)
    sleep(2)
    click_on("Save")
    sleep(2)
  end
  
  Then('the EOI must be created') do
    db_expression_of_interest = ExpressionOfInterest.last
    
    puts "\n####EOI####\n"
    puts db_expression_of_interest.to_json         

    db_expression_of_interest.entity_id.should == @investment_opportunity.entity_id
    db_expression_of_interest.investment_opportunity_id.should == @investment_opportunity.id
    db_expression_of_interest.investor_id.should == @expression_of_interest.investor_id
    db_expression_of_interest.amount_cents.should == @expression_of_interest.amount_cents
    db_expression_of_interest.details.to_plain_text.should == @expression_of_interest.details.to_plain_text
    @expression_of_interest = db_expression_of_interest
  end
  
  Then('I should see the EOI details on the details page') do
    visit(expression_of_interest_path(@expression_of_interest))
    expect(page).to have_content(@expression_of_interest.investor.investor_name)
    expect(page).to have_content(money_to_currency @expression_of_interest.amount)
    expect(page).to have_content(@expression_of_interest.details.to_plain_text)
    expect(page).to have_content(@expression_of_interest.user.full_name)
  end
  
  Then('I should see the EOI in all EOIs page') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    expect(page).to have_content(@expression_of_interest.investor.investor_name)
    expect(page).to have_content(money_to_currency @expression_of_interest.amount)
    expect(page).to have_content(@expression_of_interest.user.full_name)
  end


  Then('the investment_opportunity eoi amount should be {string}') do |amount|
    puts @investment_opportunity.reload.to_json
    @investment_opportunity.eoi_amount_cents.should == amount.to_i
  end
  
  Then('when the EOI is approved') do
    visit(investment_opportunity_path(@investment_opportunity))
    click_on "Interests"
    within("#expression_of_interest_#{@expression_of_interest.id}") do
      click_on "Approve"
    end
    sleep(1)
  end