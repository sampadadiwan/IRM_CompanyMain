Given("a Bulk Upload is performed for FundRatios with file {string}") do |file_name|
  visit(fund_path(@fund))
  click_on("Ratios")
  find("#fund_ratios_actions").click
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  sleep(2)
  click_on("Save")
  sleep(10)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should == 0
end

Given("there is a CapitalCommitment with {string}") do |arg|
  capital_commitment = CapitalCommitment.last
  key_values(capital_commitment, arg)
  capital_commitment.save!
  investor = Investor.find_by(category: "Portfolio Company")
  investor.investor_name = "Portfolio Company 1"
  investor.save!
end


And("I should find Fund Ratios created with correct data for Fund") do
  visit(fund_path(@fund))
  click_on("Ratios")
  sleep(2)
  expect(page).to have_content("XIRR")
  expect(page).to have_content("27.95 %")
end

And("I should find Fund Ratios created with correct data for API") do
  fund_ratio = FundRatio.find_by(owner: AggregatePortfolioInvestment.last)
  expect(fund_ratio.name).to(eq("RVPI"))
  expect(fund_ratio.value).to(eq("0.14273e1".to_d))
  expect(fund_ratio.display_value).to(eq("1.43 x"))
  expect(fund_ratio.end_date).to(eq(Date.parse("2022-03-31")))
end

And("I should find Fund Ratios created with correct data for Capital Commitment") do
  visit(capital_commitment_path(CapitalCommitment.last))
  click_on("Ratios")
  expect(page).to have_content("XIRR")
  expect(page).to have_content("23.45 %")
  expect(page).to have_content("31/03/2022")
end

Then("the Fund ratios must be updated") do
  fund_ratio = FundRatio.find_by(name: "Fund Utilization")
  expect(fund_ratio.value).to(eq(-0.4521e0,))
  expect(fund_ratio.notes).to(eq("Updated"))
  expect(fund_ratio.label).to(eq("Updated"))
end


Given('given the fund_ratios are computed for the date {string}') do |end_date|
  FundRatiosJob.perform_now(@fund.id, nil, Date.parse(end_date), User.first.id, true, return_cash_flows: true)
end

Then('the fund ratios computed must match the ratios in {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  count = 0
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    user_data = [headers, row].transpose.to_h
    # puts "Checking import of #{user_data}"
    folio_id = user_data["Folio No"]
    investor_name = user_data["Investor"]&.strip
    name = user_data["Name"]
    end_date = user_data["End Date"]
    end_date = end_date.is_a?(String) ? Date.parse(end_date) : end_date

    cc = folio_id.present? ? @entity.capital_commitments.where(folio_id:).first : nil
    owner = user_data["Owner Id"].present? ? user_data["Owner Type"].constantize.find(user_data["Owner Id"]) : nil
    fund_ratio = FundRatio.where(name:, capital_commitment: cc, owner:, end_date:).first

    if fund_ratio
      # puts "Found fund ratio for investor #{investor_name} with end date #{end_date}"
      # ap fund_ratio
      match = fund_ratio.value == user_data["Value"].to_d
      puts "Fund Ratio #{fund_ratio.name}: #{fund_ratio.owner} #{fund_ratio.value}, Expected Value: #{user_data["Value"].to_d}, Display Value: #{user_data["Display Value"]}, #{match}"

      # fund_ratio.value.should == user_data["Value"].to_d
      # fund_ratio.display_value.should == user_data["Display Value"]
      count += 1 if match
    else
      puts "No fund ratio found for row #{user_data}"
      count += 0
    end

  end

  puts "Total Fund Ratios matched: #{count}"
  puts "Total Fund Ratios in DB: #{FundRatio.all.count}"
  count.should == FundRatio.all.count
end


Given('I have an Excel file {string}') do |file_path|
  @xls_path = file_path
  @workbook = Roo::Spreadsheet.open(@xls_path)
end

When('I read all sheets and compute XIRR') do
  @results = []

  @workbook.sheets.each do |sheet|
    @workbook.default_sheet = sheet
    cashflows = XirrCashflow.new

    (1..@workbook.last_row).each do |i|
      amount = @workbook.cell(i, 1)
      date = @workbook.cell(i, 2)
      type = @workbook.cell(i, 3)

      next if amount.nil? || date.nil?
      puts "Row #{i}: Amount: #{amount}, Date: #{date}, Type: #{type}"

      if type.to_s.downcase == 'output'
        @expected_xirr = amount.round(2)
        break
      else
        cashflows << XirrTransaction.new(amount, date: Date.parse(date.to_s), notes: type.to_s)
      end
    end

    puts "Processing sheet: #{sheet}"
    puts "Cashflows: #{cashflows}"
    puts "Expected XIRR: #{@expected_xirr}"

    lxirr = XirrApi.new.xirr(cashflows, "xirr_#{sheet}") || 0
    puts "Computed XIRR: #{lxirr}"
    computed_xirr = (lxirr).round(2)

    @results << { sheet: sheet, expected: @expected_xirr, actual: computed_xirr }
  end
end

Then('each computed XIRR should match the expected output') do
  ap @results
  @results.each do |result|
    expect(result[:actual]).to be_within(0.01).of(result[:expected]),
      "XIRR mismatch on sheet #{result[:sheet]}: expected #{result[:expected]}, got #{result[:actual]}"
  end
end


Then('the fund ratios must be computed in tracking currency also') do
  tracking_currency = @fund.tracking_currency
  @fund.investors.portfolio_companies.each do |pc|
    expect(FundRatio.where(owner: pc).where("name like ?", "IRR (#{tracking_currency})%").count).to eq(FundRatio.where(owner: pc).where("name like ?", "IRR%").count/2)
    expect(FundRatio.where(owner: pc).where("name like ?", "MOIC (#{tracking_currency})%").count).to eq(FundRatio.where(owner: pc).where("name like ?", "MOIC%").count/2)
  end
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "IRR (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "IRR%").count/2)
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "MOIC (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "MOIC%").count/2)
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "XIRR (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "XIRR%").count/2)
end
