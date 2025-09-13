include CurrencyHelper

  When('I create a new portfolio investment {string}') do |args|



    @new_portfolio_investment = FactoryBot.build(:portfolio_investment, entity: @entity, fund: @fund)
    key_values(@new_portfolio_investment, args)

    portfolio_company = @entity.investors.portfolio_companies.where(investor_name: @new_portfolio_investment.portfolio_company_name).first
    investment_instrument = portfolio_company.investment_instruments.sample

    @new_portfolio_investment.portfolio_company = portfolio_company
    @new_portfolio_investment.investment_instrument = investment_instrument
    @new_portfolio_investment.compute_amount_cents

    visit(fund_path(@fund))
    #sleep(1)
    click_on "Portfolio"
    click_on "New Investment"


    puts @new_portfolio_investment.to_json

    select(portfolio_company.investor_name, from: "portfolio_investment_portfolio_company_id")
    select(investment_instrument.name, from: "portfolio_investment_investment_instrument_id")
    fill_in('portfolio_investment_ex_expenses_base_amount', with: @new_portfolio_investment.ex_expenses_base_amount)
    fill_in('portfolio_investment_quantity', with: @new_portfolio_investment.quantity)

    click_on "Save"
    sleep(1)
  end

  Then('a portfolio investment should be created') do
    @portfolio_investment = PortfolioInvestment.last
    @portfolio_investment.quantity.should == @new_portfolio_investment.quantity
    @portfolio_investment.amount.should == @new_portfolio_investment.amount
    @portfolio_investment.base_amount.should == @new_portfolio_investment.base_amount
    @portfolio_investment.ex_expenses_base_amount.should == @new_portfolio_investment.ex_expenses_base_amount
    if @portfolio_investment.investment_instrument.currency != @portfolio_investment.fund.currency
      @portfolio_investment.amount_cents.should == @portfolio_investment.convert_currency(@portfolio_investment.investment_instrument.currency, @portfolio_investment.fund.currency, @portfolio_investment.base_amount_cents, @portfolio_investment.investment_date)
      @portfolio_investment.amount_cents.should_not == @portfolio_investment.base_amount_cents
    end
    @portfolio_investment.portfolio_company_name.should == @new_portfolio_investment.portfolio_company_name
    @portfolio_investment.investment_instrument.name.should == @investment_instrument.name
  end

  Then('I should see the portfolio investment details on the details page') do
    expect(page).to have_content(@fund.name)
    expect(page).to have_content(@entity.name)
    expect(page).to have_content(@portfolio_investment.investment_date.strftime("%d/%m/%Y"))
    expect(page).to have_content(@portfolio_investment.portfolio_company_name)
    expect(page).to have_content(@portfolio_investment.quantity)
    expect(page).to have_content(@portfolio_investment.investment_instrument)
    expect(page).to have_content( money_to_currency @portfolio_investment.amount )
    expect(page).to have_content( money_to_currency @portfolio_investment.base_amount ) if @portfolio_investment.investment_instrument.currency != @portfolio_investment.fund.currency
  end


  Given('there are {string} portfolio investments {string}') do |count, args|
    (1..count.to_i).each do |i|
      pi = FactoryBot.build(:portfolio_investment, entity: @entity, fund: @fund, investment_instrument: @investment_instrument)
      key_values(pi, args)
      result = PortfolioInvestmentCreate.wtf?(portfolio_investment: pi)
      # binding.pry if result.failure?
      result.success?.should == true
      puts "\n#########PortfolioInvestment##########\n"
      puts pi.to_json
    end

  end

  Then('an aggregate portfolio investment should be created') do
    @api = AggregatePortfolioInvestment.last
    @api.quantity.should == PortfolioInvestment.all.sum(:quantity)
    @api.bought_quantity.should == PortfolioInvestment.buys.sum(:quantity)
    @api.bought_amount_cents.should == PortfolioInvestment.buys.sum(:net_bought_amount_cents)
    @api.sold_quantity.should == PortfolioInvestment.sells.sum(:quantity)
    @api.sold_amount_cents.should == PortfolioInvestment.sells.sum(:net_amount_cents)
    quantity = PortfolioInvestment.buys.sum(:quantity)
    @api.avg_cost_cents.round.should == (PortfolioInvestment.buys.sum(:amount_cents) / quantity).round(0) if quantity > 0
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




Then('an aggregate portfolio investment should not be created') do
  AggregatePortfolioInvestment.count.should == 0
end

Then('the aggregate portfolio investment should have the right rollups') do
  @api = AggregatePortfolioInvestment.last
  @api.quantity.should == PortfolioInvestment.buys.sum(:net_quantity)
  @api.ex_expenses_amount_cents.should == PortfolioInvestment.sum(:ex_expenses_amount_cents)
  @api.transfer_amount_cents.should == PortfolioInvestment.sum(:transfer_amount_cents)
  @api.transfer_quantity.should == PortfolioInvestment.sum(:transfer_quantity)
  @api.cost_of_remaining_cents.should == PortfolioInvestment.sum(:cost_of_remaining_cents)
  @api.unrealized_gain_cents.should == PortfolioInvestment.sum(:unrealized_gain_cents)
  @api.gain_cents.should == PortfolioInvestment.sum(:gain_cents)
  @api.fmv_cents.should == PortfolioInvestment.sum(:fmv_cents)
  @api.sold_amount_cents.should == PortfolioInvestment.sells.sum(:amount_cents)
  @api.sold_quantity.should == PortfolioInvestment.sells.sum(:quantity)
  @api.bought_amount_cents.should == PortfolioInvestment.buys.sum(:amount_cents)
  @api.net_bought_amount_cents.should == PortfolioInvestment.buys.sum(:net_bought_amount_cents)
  @api.bought_quantity.should == PortfolioInvestment.buys.sum(:quantity)
  @api.instrument_currency_fmv_cents.should == PortfolioInvestment.buys.sum(:instrument_currency_fmv_cents)
  @api.instrument_currency_cost_of_remaining_cents.should == PortfolioInvestment.buys.sum(:instrument_currency_cost_of_remaining_cents)
  @api.instrument_currency_unrealized_gain_cents.should == PortfolioInvestment.buys.sum(:instrument_currency_unrealized_gain_cents)
end


Given('there is a valuation {string} for the portfolio company') do |args|
  @portfolio_company = @entity.investors.portfolio_companies.last
  @valuation = FactoryBot.build(:valuation, entity: @entity, owner: @portfolio_company, investment_instrument: @investment_instrument, valuation_date: Date.today)
  key_values(@valuation, args)
  @valuation.save!
end

Given('the portfolio companies have investment instruments {string}') do |args|
  @entity.investors.portfolio_companies.each do |pc|
    @investment_instrument = FactoryBot.build(:investment_instrument, entity: @entity, portfolio_company: pc)
    key_values(@investment_instrument, args)
    @investment_instrument.save!
  end
end

Then('the fmv must be calculated for the portfolio') do
  PortfolioInvestment.all.each do |pi|
    if pi.buy?
      pi.net_quantity.should == pi.quantity + pi.sold_quantity - pi.transfer_quantity
      pi.fmv_cents.should == (pi.net_quantity * @valuation.per_share_value_in(pi.fund.currency, pi.investment_date))
    else
      pi.net_quantity.should == pi.quantity
      pi.fmv_cents.should == 0
      pi.gain_cents.should == pi.amount_cents.abs + pi.cost_of_sold_cents
    end
  end
end


Then('There should be {string} portfolio investments created') do |count|
  PortfolioInvestment.count.should == count.to_i
end

Then('the portfolio investments must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  portfolio_investments = @fund.portfolio_investments.include_proforma.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    pi = portfolio_investments[idx-1]
    puts "Checking import of #{pi.portfolio_company_name}"
    ap pi
    pi.portfolio_company_name.should == user_data["Portfolio Company Name"].strip
    pi.fund.name.should == user_data["Fund"]
    pi.ex_expenses_base_amount_cents.should == user_data["Amount (Excluding Expenses)"].to_d * 100
    pi.base_amount_cents.should == pi.ex_expenses_base_amount_cents + pi.expense_cents
    if pi.investment_instrument.currency != pi.fund.currency
      pi.amount_cents.should == pi.convert_currency(pi.investment_instrument.currency, pi.fund.currency, pi.base_amount_cents, pi.investment_date)
    end
    pi.quantity.should == user_data["Quantity"].to_d
    pi.investment_instrument.name.should == user_data["Instrument"]
    pi.investment_instrument.investment_domicile.should == user_data["Investment Domicile"]
    pi.notes.should == user_data["Notes"]
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
  sleep(2)
  click_on("Save")
  sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  sleep(4)
  @import_upload = ImportUpload.last
  @import_upload.failed_row_count.should == 0
end

Then('There should be {string} valuations created') do |count|
  Valuation.count.should == count.to_i
end

Then('the valuations must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  valuations = @entity.valuations.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    val = valuations[idx-1]
    puts "Checking import of #{val.owner.investor_name}"
    val.investment_instrument.name.should == user_data["Instrument"].strip
    val.valuation_date.should == Date.parse(user_data["Valuation Date"].to_s)
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
    expect(pa.sold_pi.quantity).to be_within(0.0001).of(PortfolioAttribution.sum(:quantity))
  end
end

Then('the aggregate portfolio investments must have cost of sold computed') do
  @fund.reload
  @fund.portfolio_investments.sells.each do |pi|
    api = pi.aggregate_portfolio_investment
    puts "Cost: #{api.cost_of_remaining_cents} = Bought Amount: #{api.bought_amount} - Cost of sold: #{api.cost_of_sold}"
    api.cost_of_sold_cents.should == api.portfolio_investments.sells.sum(:cost_of_sold_cents)
    # binding.pry if api.cost_of_remaining_cents != api.bought_amount_cents + api.cost_of_sold_cents
    api.cost_of_remaining_cents.should == api.bought_amount_cents + api.cost_of_sold_cents
  end
end


Given('I create a new stock adjustment {string}') do |args|
  puts "#### #{args}"
  @orig_portfolio_investments = PortfolioInvestment.includes(portfolio_company: :valuations).all.to_a
  @orig_portfolio_attributions = PortfolioAttribution.all.to_a

  @stock_adjustment = StockAdjustment.new(portfolio_company: @investor, entity_id: @investor.entity_id, user_id: User.first.id, investment_instrument: @investment_instrument)
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
    net_amount_cents = opi.buy? ? opi.net_quantity * opi.cost_cents : opi.amount_cents
    opi.net_amount_cents.should == net_amount_cents
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


Given('Given I upload the portfolio companies') do
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


Given('there is an investment instrument for the portfolio company {string}') do |string|
  @investment_instrument = FactoryBot.build(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company)
  key_values(@investment_instrument, string)
  @investment_instrument.save!
end

Given('The user generates all fund reports for the fund') do
  %w[CorpusDetails InformationOnInvestments InfoOnInvestors SEBIReport].each do |report_name|
    visit(fund_path(@fund))
    click_button("Fund Reports")
    click_link("All Reports")
    click_link("New Fund Report")
    select(@fund.name, from: "fund_report_fund_id")
    select(report_name, from: "fund_report_name")
    fill_in('fund_report_start_date', with: "2020-01-01", wait: 100)
    fill_in('fund_report_end_date', with: "2024-01-01", wait: 100)
    click_button("Save")
    sleep(2)
  end
end

Then('There should be {string} reports created') do |string|
  expect(page).to have_content("Fund report will be generated, please check back in a few mins")
  FundReport.where(fund_id: @fund.id).count.should == string.to_i
  SebiReportJob::ALL_REPORT_JOBS.each do |report_name|
    FundReport.where(fund_id: @fund.id).pluck(:name).include?(report_name).should == true
  end
end

Then('Sebi report should be generated for the fund') do
  # doc name should include SEBI Report
  Document.last.owner_id.should == @fund.id
  Document.last.name.include?("SEBI Report").should == true
  doc = Document.last
  ff = doc.file.download
  generated_excel =  Spreadsheet.open(Rails.root.join(ff.path))
  result_excel = Spreadsheet.open(Rails.root.join("./public/sample_uploads/result_sebi_report.xls"))
  generated_excel.worksheets.count.should == result_excel.worksheets.count
  generated_excel.worksheets.each_with_index do |ws, idx|
    ws.name.should == result_excel.worksheets[idx].name
    ws.rows.count.should == result_excel.worksheets[idx].rows.count
    result_sheet_rows = result_excel.worksheets[idx].rows

    ws.rows.each_with_index do |row, ridx|
      expect(row.compact).to(eq(result_sheet_rows[ridx].compact))
    end
  end
end




Given('I create a new stock conversion {string}  from {string} to {string}') do |args, from_instrument, to_instrument|

  @from_portfolio_investment = PortfolioInvestment.buys.sample
  @from_instrument = @from_portfolio_investment.investment_instrument
  # Grab the to_instrument from the portfolio company
  @to_instrument = InvestmentInstrument.new
  key_values(@to_instrument, to_instrument)
  @to_instrument = @from_portfolio_investment.portfolio_company.investment_instruments.where(name: @to_instrument.name).first

  @stock_conversion = StockConversion.new(entity_id: @entity.id, from_portfolio_investment: @from_portfolio_investment, to_instrument: @to_instrument, from_instrument: @from_instrument, fund: @fund, conversion_date: Date.today)
  key_values(@stock_conversion, args)

  StockConverter.wtf?(stock_conversion: @stock_conversion).success?.should == true
end

Then('the from portfolio investments must be adjusted') do
  @from_portfolio_investment.reload
  if StockConversion.where(id: @stock_conversion.id).count == 1
    puts "Checking from portfolio investment for conversions"
    @from_portfolio_investment.transfer_quantity.should == @stock_conversion.from_quantity
    @from_portfolio_investment.transfer_amount_cents.should == -@stock_conversion.from_quantity * @from_portfolio_investment.cost_cents
    @from_portfolio_investment.net_quantity.should == @from_portfolio_investment.quantity + @from_portfolio_investment.sold_quantity - @stock_conversion.from_quantity
    @from_portfolio_investment.notes.should == @stock_conversion.notes
  else
    puts "Checking from portfolio investment for reversals"
    @from_portfolio_investment.transfer_quantity.should == 0
    @from_portfolio_investment.transfer_amount_cents.should == 0
    @from_portfolio_investment.net_quantity.should == @from_portfolio_investment.quantity + @from_portfolio_investment.sold_quantity
    @from_portfolio_investment.notes.should == ""
  end
  # Check the api
  api = @from_portfolio_investment.aggregate_portfolio_investment
  api.transfer_amount_cents.should == @from_portfolio_investment.aggregate_portfolio_investment.portfolio_investments.sum(:transfer_amount_cents)
  api.cost_of_remaining_cents.should == api.bought_amount_cents + api.transfer_amount_cents + api.cost_of_sold_cents
end

Then('the to portfolio investments must be created') do
  @stock_conversion.reload
  @to_portfolio_investment = @stock_conversion.to_portfolio_investment
  @to_portfolio_investment.entity_id.should == @from_portfolio_investment.entity_id
  @to_portfolio_investment.fund_id.should == @from_portfolio_investment.fund_id
  @to_portfolio_investment.form_type_id.should == @from_portfolio_investment.form_type_id
  @to_portfolio_investment.portfolio_company_id.should == @from_portfolio_investment.portfolio_company_id
  @to_portfolio_investment.portfolio_company_name.should == @from_portfolio_investment.portfolio_company_name
  @to_portfolio_investment.investment_date.should == @from_portfolio_investment.investment_date
  @to_portfolio_investment.quantity.should == @stock_conversion.to_quantity
  @to_portfolio_investment.folio_id.should == @from_portfolio_investment.folio_id
  @to_portfolio_investment.capital_commitment_id.should == @from_portfolio_investment.capital_commitment_id
  @to_portfolio_investment.investment_instrument_id.should == @stock_conversion.to_instrument_id
  @to_portfolio_investment.notes.should == @stock_conversion.notes
  @to_portfolio_investment.base_amount_cents.should == @to_portfolio_investment.convert_currency(@from_portfolio_investment.investment_instrument.currency, @to_portfolio_investment.investment_instrument.currency, @from_portfolio_investment.base_cost_cents, @from_portfolio_investment.investment_date) * @stock_conversion.from_quantity

  @stock_conversion.to_portfolio_investment_id.should == @to_portfolio_investment.id
end


Then('the APIs must have the right quantity post transfer') do
  AggregatePortfolioInvestment.all.each do |api|
    api.quantity.should == api.portfolio_investments.buys.sum(:net_quantity)
    api.transfer_amount_cents.should == api.portfolio_investments.sum(:transfer_amount_cents)
  end
end

Then('When I reverse the stock conversion') do
  StockConverterReverse.wtf?(stock_conversion: @stock_conversion).success?.should == true
end

Then('the to portfolio investments must be deleted') do
  PortfolioInvestment.where(id: @stock_conversion.to_portfolio_investment_id).count.should == 0
end

Then('the stock conversion must be deleted') do
  StockConversion.where(id: @stock_conversion.id).count.should == 0
end

Given('I add widgets for the aggregate portfolio investment') do
  visit(aggregate_portfolio_investment_path(@api))
  click_on("Widgets")
  click_on("New Widget")
  fill_in('ci_widget_title', with: "Left Widget")
  select("Left", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Left Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Left Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfull")

  visit(aggregate_portfolio_investment_path(@api))
  click_on("Widgets")
  click_on("New Widget")
  fill_in('ci_widget_title', with: "Center Widget")
  select("Center", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Center Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Center Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfull")

  visit(aggregate_portfolio_investment_path(@api))
  click_on("Widgets")
  click_on("New Widget")
  fill_in('ci_widget_title', with: "Right Widget")
  select("Right", from: "ci_widget_image_placement")
  details_top_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[3]/trix-editor")
  details_top_element.set("Right Widget Intro")
  details_element = find(:xpath, "/html/body/div[2]/div[1]/div/div/div[3]/div/div/div[2]/form/div[4]/trix-editor")
  details_element.set("Right Widget Details")
  # fill_in('ci_widget_details_top', with: "Right Widget Intro")
  # fill_in('ci_widget_details', with: "Right Widget Details")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)
  click_on("Save")
  expect(page).to have_content("successfull")
end

Given('I add track record for the aggregate portfolio investment') do
  visit(aggregate_portfolio_investment_path(@api))
  click_on("Track Record")
  click_on("New Track Record")
  fill_in('ci_track_record_name', with: "Test Track Record")
  fill_in('ci_track_record_prefix', with: "good")
  fill_in('ci_track_record_value', with: "250000")
  fill_in('ci_track_record_suffix', with: "bad")
  fill_in('ci_track_record_details', with: "Track record details")
  click_on("Save")
  expect(page).to have_content("successfull")
end

Given('I add preview documents for the aggregate portfolio investment') do
  visit(aggregate_portfolio_investment_path(@api))
  # Click the documents tab
  within(".api_details") do
    click_on("Documents")
    sleep(1)
    # Click the new document button
    find("#doc_actions").click
    click_on("New Document")
  end

  fill_in('document_name', with: "Test Document")
  fill_in('document_tag_list', with: "test, preview")
  attach_file('files[]', File.absolute_path("./public/img/logo_big.png"), make_visible: true)
  sleep(0.5)

  click_on("Save")


end

When('I go to aggregate portfolio investment preview') do
  visit(aggregate_portfolio_investment_path(@api))
  click_on("Preview")
end

Then('I can see all the preview details') do
  @api.ci_widgets.each do |widget|
    expect(page).to have_content(widget.title)
    expect(page).to have_content(widget.details_top.gsub(/<\/?div>/, ''))
    expect(page).to have_content(widget.details.gsub(/<\/?div>/, ''))
  end
  @api.ci_track_records.each do |track_record|
    expect(page).to have_content(track_record.name)
    expect(page).to have_content(track_record.prefix)
    expect(page).to have_content(track_record.value)
    expect(page).to have_content(track_record.suffix)
    expect(page).to have_content(track_record.details.gsub(/<\/?div>/, ''))
  end
  @api.documents.each do |doc|
    expect(page).to have_content(doc.name)
  end
end


When('I upload investment instruments file {string}') do |string|
  visit("/import_uploads")
  click_on("Upload")
  fill_in('import_upload_name', with: "Instrument Upload")
  select("InvestmentInstrument", from: "import_upload_import_type")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{string}"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
end

Then('{string} investment instruments should be created') do |count|
  count = count.to_i
  InvestmentInstrument.count.should == count
end

Then('I should see the investment instrument details on the import page') do
  @import_upload = ImportUpload.last
  visit(import_upload_path(@import_upload))
  expect(page).to have_content("Investment Instruments")
  InvestmentInstrument.where(import_upload_id: @import_upload.id).each do |ii|
    expect(page).to have_content(ii.name)
    expect(page).to have_content(ii.currency)
    expect(page).to have_content(ii.portfolio_company.investor_name)
  end
end

Then('the aggregate portfolio investment should have a quantity of {string}') do |quantity|
  @api = AggregatePortfolioInvestment.last
  @api.quantity.should == quantity.to_i
end

Then('the total number of portfolio investments with snapshots should be {string}') do |count|
  # Get all the snapshots of the fund
  fund_ids = Fund.with_snapshots.where(orignal_id: @fund.id).pluck(:id)
  # Get all the PIs including snapshots of the orignal fund
  PortfolioInvestment.unscoped.with_snapshots.where(fund_id: fund_ids).count.should == count.to_i
end

Given('I generate a portfolio as of report for {string}') do |string|
  @fund ||= Fund.last
  visit("/investors/portfolio_investments_report_all?fund_id=#{@fund.id}")
  fill_in('as_of', with: Time.zone.parse(string))
  click_on("Generate")
  sleep(1)
  expect(page).to have_content("Report generation started, please check back in a few mins")
end

Then('the portfolio as of report should be generated for the date {string} with expected data') do |string|
  @report = Document.last
  file = @report.file.download
  data = Roo::Spreadsheet.open(file.path)
  result_excel = Roo::Spreadsheet.open("./public/result_portfolio_as_of_report_#{string.gsub('/','')}.xlsx")

  data.sheets.each do |sheet|
    worksheet = data.sheet(sheet)

    worksheet.each_with_index do |row, idx|
      expect(row).to eq(result_excel.sheet(sheet).row(idx+1))
    end
  end
end


Given('I go to view the fund') do
  @fund ||= Fund.last
  visit(fund_path(@fund))
end

Given('I click on {string}') do |string|
  click_on(string)
end

Given('I fill the scenario form') do
  @scenario_name = "Test Scenario #{rand(1000)}"
  fill_in('portfolio_scenario_name', with: @scenario_name)
end

Given('I fill the new scenario investment form') do
  @investment_name = "Test Investment #{rand(1000)}"
  @portfolio_company ||= @entity.investors.portfolio_companies.first
  @investment_instrument ||= @portfolio_company.investment_instruments.first
  @date = Date.today - rand(100).days
  fill_in('scenario_investment_transaction_date', with: @date)
  select(@portfolio_company.investor_name, from: "scenario_investment_portfolio_company_id")
  select(@investment_instrument.name, from: "scenario_investment_investment_instrument_id")
  @price = 1000 + rand(2000)
  @quantity = 100 + rand(200)
  fill_in('scenario_investment_price', with: @price)
  fill_in('scenario_investment_quantity', with: @quantity)
  @notes = "Test investment notes #{rand(1000)}"
  fill_in('scenario_investment_notes', with: @notes)
end

Then('I should see the new investment added on the portfolio scenarios page') do
  expect(page).to have_content(money_to_currency(@price))
  expect(page).to have_content(@portfolio_company.investor_name)
  expect(page).to have_content(@notes)
  expect(page).to have_content(@date.strftime("%d/%m/%Y"))
end

Given('I partally fill the new scenario investment form') do
  @date = Date.today - rand(100).days
  fill_in('scenario_investment_transaction_date', with: @date)
end

Then('I should see the errors on the same page') do
  expect(page).to have_content("Portfolio company must exist")
  expect(page).to have_content("Investment instrument must exist")
  expect(page).to have_content("Price cents must be greater than 0")
end

Given('I go to API show page') do
  @api ||= AggregatePortfolioInvestment.last
  visit(aggregate_portfolio_investment_path(@api))
end

Given('I fill in the new investment form') do
  @date = Date.today - rand(100).days
  fill_in("portfolio_investment_investment_date", with: @date)
  @amount = 1000 + rand(1000)
  fill_in("portfolio_investment_ex_expenses_base_amount", with: @amount)
  @quantity = 10 + rand(10)
  fill_in("portfolio_investment_quantity", with: @quantity)
  @notes = "Test investment notes #{rand(1000)}"
  fill_in("portfolio_investment_notes", with: @notes)
end


Then('I should see the PI details on the details page') do
  @portfolio_investment = PortfolioInvestment.last
  @api = @portfolio_investment.aggregate_portfolio_investment
  expect(page).to have_content(@portfolio_investment.portfolio_company.to_s)
  expect(page).to have_content(@portfolio_investment.investment_instrument.to_s)
  expect(page).to have_content(@date.strftime("%d/%m/%Y"))
  expect(page).to have_content(@quantity)
  expect(page).to have_content(money_to_currency(@amount))
  expect(page).to have_content(@notes)
end

Given('I fill in the new investment form with different Portfolio Company') do
  @portfolio_company = Investor.portfolio_companies.second
  @api = AggregatePortfolioInvestment.where(portfolio_company_id: @portfolio_company.id).first
  @investment_instrument = @portfolio_company.investment_instruments.first
  select(@portfolio_company.name, from: "portfolio_investment_portfolio_company_id")
  sleep(1)
  select(@investment_instrument.name, from: "portfolio_investment_investment_instrument_id")
  @date = Date.today - rand(100).days
  fill_in("portfolio_investment_investment_date", with: @date)
  @amount = 1000 + rand(1000)
  fill_in("portfolio_investment_ex_expenses_base_amount", with: @amount)
  @quantity = 10 + rand(10)
  fill_in("portfolio_investment_quantity", with: @quantity)
  @notes = "Test investment notes #{rand(1000)}"
  fill_in("portfolio_investment_notes", with: @notes)
end

Then('The Portfolio Scenario should run successfully') do
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  # This happens too quick before the redirect with notice
  # expect(page).to have_content("Portfolio Scenario: #{@scenario_name} has been run successfully.", wait: 5)
  expect(page).to have_content("XIRR")
  expect(page).to have_content("MOIC")
  expect(page).to have_content("Portfolio Company Metrics")
end

Then('The Portfolio Scenario Should be finalized') do
  @portfolio_scenario ||= PortfolioScenario.where(name: @scenario_name).last
  expect(page).to have_content("Finalization enqueued for #{@scenario_name}")
  # This happens too quick before the redirect with notice
  # expect(page).to have_content("Fund ratios for #{@scenario_name} were successfully created.", wait: 5)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(@portfolio_scenario.fund_ratios.count).to be > 0
  portfolio_companies_ids = @portfolio_scenario.fund.portfolio_investments.pluck(:portfolio_company_id).uniq
  per_company_fund_ratios = 2
  fund_ratios_count = 2
  expect(@portfolio_scenario.fund_ratios.count).to eq((portfolio_companies_ids.count * per_company_fund_ratios) + fund_ratios_count)
  expect(page).to have_content("Fund Ratios")
end