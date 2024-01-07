include CurrencyHelper

  When('I create a new portfolio investment {string}') do |args|
    @new_portfolio_investment = FactoryBot.build(:portfolio_investment, entity: @entity, fund: @fund)
    key_values(@new_portfolio_investment, args)

    visit(fund_path(@fund))
    sleep(1)
    click_on "Portfolio"    
    click_on "New Investment"
    
    portfolio_company = @entity.investors.portfolio_companies.where(investor_name: @new_portfolio_investment.portfolio_company_name).first

    puts @new_portfolio_investment.to_json

    select(portfolio_company.investor_name, from: "portfolio_investment_portfolio_company_id")
    fill_in('portfolio_investment_amount', with: @new_portfolio_investment.amount)
    fill_in('portfolio_investment_quantity', with: @new_portfolio_investment.quantity)
    select(@new_portfolio_investment.category, from: 'portfolio_investment_category')
    select(@new_portfolio_investment.sector, from: 'portfolio_investment_sector')

    click_on "Save"    
    sleep(1)
  end
  
  Then('a portfolio investment should be created') do
    @portfolio_investment = PortfolioInvestment.last
    @portfolio_investment.quantity.should == @new_portfolio_investment.quantity
    @portfolio_investment.amount.should == @new_portfolio_investment.amount
    @portfolio_investment.category.should == @new_portfolio_investment.category
    @portfolio_investment.portfolio_company_name.should == @new_portfolio_investment.portfolio_company_name
  end

  Then('I should see the portfolio investment details on the details page') do
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@entity.name)
    expect(page).to have_content(@portfolio_investment.investment_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@portfolio_investment.portfolio_company_name)
    expect(page).to have_content(@portfolio_investment.quantity)
    expect(page).to have_content(@portfolio_investment.category)
    expect(page).to have_content( money_to_currency @portfolio_investment.amount)
  end


  Given('there are {string} portfolio investments {string}') do |count, args|
    (1..count.to_i).each do |i|
      pi = FactoryBot.build(:portfolio_investment, entity: @entity, fund: @fund)
      key_values(pi, args)
      pi.save!
      puts "\n#########PortfolioInvestment##########\n"
      puts pi.to_json
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
    pi.fmv_cents.should == (pi.net_quantity * @valuation.per_share_value_cents)
  end
end


Then('There should be {string} portfolio investments created') do |count|
  PortfolioInvestment.count.should == count.to_i
end

Then('the portfolio investments must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportPreProcess.new.get_headers(data.row(1)) # get header row

  portfolio_investments = @fund.portfolio_investments.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    pi = portfolio_investments[idx-1]
    puts "Checking import of #{pi.portfolio_company_name}"
    ap pi
    pi.portfolio_company_name.should == user_data["Portfolio Company Name"].strip
    pi.fund.name.should == user_data["Fund"]
    pi.amount_cents.should == user_data["Amount"].to_d * 100
    pi.quantity.should == user_data["Quantity"].to_d
    pi.category.should == user_data["Category"]
    pi.sub_category.should == user_data["Sub Category"]
    pi.startup.should == (user_data["Startup"] == "Yes")
    pi.investment_domicile.should == user_data["Investment Domicile"]
    pi.notes.should == user_data["Notes"]
    pi.commitment_type.should == user_data["Type"]
    if pi.commitment_type == "CoInvest"
      pi.capital_commitment_id.should == @fund.capital_commitments.where(folio_id: user_data["Folio No"]).first.id
    end  
    pi.investment_date.should == Date.parse(user_data["Investment Date"].to_s)
    pi.properties["custom_field_1"].should == user_data["Custom Field 1"]    
    pi.import_upload_id.should == ImportUpload.last.id
  end
end


Given('Given I upload {string} file for portfolio companies of the fund') do |file|
  @import_file = file
  visit(new_import_upload_path("import_upload[entity_id]": @fund.entity_id, "import_upload[owner_id]": @fund.id, "import_upload[owner_type]": "Fund", "import_upload[import_type]": "Valuation"))
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(1)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
end

Then('There should be {string} valuations created') do |count|
  Valuation.count.should == count.to_i
end

Then('the valuations must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportPreProcess.new.get_headers(data.row(1)) # get header row

  valuations = @entity.valuations.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    val = valuations[idx-1]
    puts "Checking import of #{val.owner.investor_name}"
    val.category.should == user_data["Category"].strip
    val.sub_category.should == user_data["Sub Category"].strip
    val.valuation_date.should == Date.parse(user_data["Valuation Date"].to_s)   
    val.valuation_cents.should == user_data["Valuation"].to_d * 100
    val.per_share_value_cents.should == user_data["Per Share Value"].to_d * 100
    val.owner.investor_name.should == user_data["Portfolio Company"].strip
    val.import_upload_id.should == ImportUpload.last.id
  end
end


Then('there must be {string} portfolio attributions created') do |count|
  PortfolioAttribution.count.should == count.to_i
  PortfolioAttribution.all.each do |pa|
    ap pa
    pa.sold_pi.sell?.should == true
    pa.sold_pi.cost_of_sold_cents.should == PortfolioAttribution.all.map{|x| x.quantity * x.bought_pi.cost_cents}.sum
    pa.sold_pi.gain_cents.should == pa.sold_pi.amount_cents + pa.sold_pi.cost_of_sold_cents
    pa.bought_pi.buy?.should == true
    pa.bought_pi.sold_quantity.should == pa.quantity
    pa.bought_pi.net_quantity.should == pa.bought_pi.quantity + pa.bought_pi.sold_quantity
    pa.sold_pi.quantity.should == PortfolioAttribution.all.sum(:quantity)
  end
end

Then('the aggregate portfolio investments must have cost of sold computed') do
  @fund.reload
  @fund.portfolio_investments.sells.each do |pi|
    # binding.pry
    pi.aggregate_portfolio_investment.cost_of_sold_cents.should == pi.aggregate_portfolio_investment.portfolio_investments.sells.sum(:cost_of_sold_cents)
  end
end


Given('I create a new stock adjustment {string}') do |args|
  puts "#### #{args}"
  @orig_portfolio_investments = PortfolioInvestment.includes(portfolio_company: :valuations).all.to_a
  @orig_portfolio_attributions = PortfolioAttribution.all.to_a
  
  @stock_adjustment = StockAdjustment.new(portfolio_company: @investor, entity_id: @investor.entity_id, user_id: User.first.id)
  key_values(@stock_adjustment, args)
  @stock_adjustment.save!
  sleep(2)
end

Then('the valuations must be adjusted') do  
  (@valuation.per_share_value_cents / @stock_adjustment.adjustment).round(0).should == @valuation.reload.per_share_value_cents.round(0) 
end

Then('the Portfolio investments must be adjusted') do
  @current_portfolio_investments = PortfolioInvestment.all
  @orig_portfolio_investments.each_with_index do |opi, idx|
    ap opi
    
    cpi = @current_portfolio_investments[idx]
    # ap cpi

    cpi.quantity.should == opi.quantity * @stock_adjustment.adjustment
    cpi.amount_cents.should == opi.amount_cents 
    # cpi.fmv_cents.should be_within(100).of(opi.fmv_cents)
    cpi.cost_of_sold_cents.should == opi.cost_of_sold_cents
    cpi.net_quantity.should == opi.net_quantity * @stock_adjustment.adjustment
    cpi.gain_cents.should be_within(100).of(opi.gain_cents)
  end
end

Then('the Portfolio attributions must be adjusted') do
  @current_portfolio_attributions = PortfolioAttribution.all
  @orig_portfolio_attributions.each_with_index do |opa, idx|
    cpa = @current_portfolio_attributions[idx]
    cpa.quantity.should == opa.quantity * @stock_adjustment.adjustment
    cpa.cost_of_sold_cents.should == opa.cost_of_sold_cents
  end
end


Given('Given I upload an the portfolio companies') do
  visit(investors_path)
  click_on("Actions")
  click_on("Upload")
  sleep(1)
  fill_in('import_upload_name', with: "Test Investor Upload")
  attach_file('files[]', File.absolute_path('./public/sample_uploads/portfolio_companies.xlsx'), make_visible: true)
  sleep(4)
  click_on("Save")
  sleep(4)
  ImportUploadJob.perform_now(ImportUpload.last.id)
end