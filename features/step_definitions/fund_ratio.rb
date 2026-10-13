Given("a Bulk Upload is performed for FundRatios with file {string}") do |file_name|
  visit(fund_path(@fund))
  click_on("Ratios")
  find("#fund_ratios_actions").click
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  wait_for_upload("./public/sample_uploads/#{file_name}") # JS direct-upload to /upload; returns once it lands (was sleep 2)
  click_on("Save")
  expect(page).to have_content("Import Upload:", wait: 15)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should
  ImportUpload.last.status.should == "Completed"
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
  expect(fund_ratio.end_date).to(eq(Date.local_parse("2022-03-31")))
end

And("I should find Fund Ratios created with correct data for Capital Commitment") do
  visit(capital_commitment_path(CapitalCommitment.last))
  # This is to scroll to the Account Entries tab and click it, otherwise the turbo_frame does not lazy load unless you scroll to it
  click_tab("Ratios")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content("XIRR", wait: 5)
  expect(page).to have_content("23.45 %")
  expect(page).to have_content("31/03/2022")
end

Then("the Fund ratios must be updated") do
  fund_ratio = FundRatio.find_by(name: "Fund Utilization")
  expect(fund_ratio.value).to(eq(-0.4521e0))
  expect(fund_ratio.notes).to(eq("Updated"))
  expect(fund_ratio.label).to(eq("Updated"))
end

Given('given the fund_ratios are computed for the date {string}') do |end_date|
  @fund_ratio_date = Date.local_parse(end_date)
  FundRatiosJob.perform_now(@fund.id, nil, @fund_ratio_date, User.first.id, true, return_cash_flows: true)
end

Then('the fund ratios computed must match the ratios in {string}') do |file_name|
  puts "RATIOS"
  FundRatio.all.each do |fr|
    # puts [fr.id, fr.name, fr.value, fr.owner_type, fr.owner_id, fr.end_date]
    puts "ratio #{fr.id} #{fr.name} : owner - #{fr.owner_type} #{fr.owner_id} - #{fr.value} #{fr.end_date}"
  end
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
    end_date = Date.local_parse(end_date) if end_date.is_a?(String)

    cc = folio_id.present? ? @entity.capital_commitments.where(folio_id:).first : nil
    owner = user_data["Owner Id"].present? ? user_data["Owner Type"].constantize.find(user_data["Owner Id"]) : nil
    puts "Finding RATIO - #{name} commitment - #{cc&.id} owner - #{user_data["Owner Type"]} #{user_data["Owner Id"]} end_date - #{end_date}"
    fund_ratio = FundRatio.where(name:, capital_commitment: cc, owner:, end_date:).first

    if fund_ratio
      # puts "Found fund ratio for investor #{investor_name} with end date #{end_date}"
      # ap fund_ratio
      match = fund_ratio.value == user_data["Value"].to_d
      if match
        count += 1
      else
        puts "MISMATCH: Fund Ratio #{fund_ratio.name} for #{fund_ratio.owner.try(:name) || fund_ratio.owner}"
        puts "  Expected: #{user_data['Value'].to_d} (Display: #{user_data['Display Value']})"
        puts "  Actual:   #{fund_ratio.value} (Display: #{fund_ratio.display_value})"
      end
    else
      puts "NOT FOUND: Fund ratio #{name} for investor #{investor_name} with end date #{end_date}"
      # count += 0
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
        cashflows << XirrTransaction.new(amount, date: Date.local_parse(date.to_s), notes: type.to_s)
      end
    end

    puts "Processing sheet: #{sheet}"
    puts "Cashflows: #{cashflows}"
    puts "Expected XIRR: #{@expected_xirr}"

    lxirr = XirrApi.new.xirr(cashflows, "xirr_#{sheet}") || 0
    puts "Computed XIRR: #{lxirr}"
    computed_xirr = lxirr.round(2)

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
    expect(FundRatio.where(owner: pc).where("name like ?", "IRR (#{tracking_currency})%").count).to eq(FundRatio.where(owner: pc).where("name like ?", "IRR%").count / 2)
    expect(FundRatio.where(owner: pc).where("name like ?", "MOIC (#{tracking_currency})%").count).to eq(FundRatio.where(owner: pc).where("name like ?", "MOIC%").count / 2)
  end
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "IRR (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "IRR%").count / 2)
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "MOIC (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "MOIC%").count / 2)
  @fund.fund_ratios.where(owner: @fund).where("name like ?", "XIRR (#{tracking_currency})%").count.should eq(@fund.fund_ratios.where(owner: @fund).where("name like ?", "XIRR%").count / 2)
end

Then('The Portfolio company MOIC ratio can be viewed properly') do
  tracking_currency = @fund.tracking_currency
  owner = @fund.investors.portfolio_companies.last
  fr = FundRatio.find_by(owner:, name: "MOIC (#{tracking_currency})")
  visit(fund_ratio_path(fr))
  expect(page).to have_content("MOIC (#{tracking_currency})")
  # expect(page).to have_content("Cost Of Remaining")
  # expect(page).to have_content("Fmv")
  # expect(page).to have_content("Sold Amount")
  # expect(page).to have_content("Bought Amount")
end

Given('I log in as user {string}') do |first_name|
  @user = User.find_by_first_name(first_name)
  steps %(
    And I am signed in as the current user
  )
end

Given('there is a PortfolioScenario {string} for the fund') do |portfolio_scenario_args|
  @user ||= User.first
  @portfolio_scenario = @fund.portfolio_scenarios.new(entity: @entity, fund: @fund, user: @user)
  key_values(@portfolio_scenario, portfolio_scenario_args)
  @portfolio_scenario.save!
end

Then('the FundRatios should be linked to the PortfolioScenario {string} from file {string}') do |portfolio_scenario_name, file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    user_data = [headers, row].transpose.to_h
    # puts "Checking import of #{user_data}"
    folio_id = user_data["Folio No"]
    name = user_data["Ratio Name"]
    end_date = user_data["End Date"]
    end_date = Date.local_parse(end_date) if end_date.is_a?(String)
    portfolio_scenario_name = user_data["Portfolio Scenario"]
    portfolio_scenario = @fund.portfolio_scenarios.find_by(name: portfolio_scenario_name)

    cc = folio_id.present? ? @entity.capital_commitments.where(folio_id:).first : nil
    fund_ratio = FundRatio.find_by(name:, capital_commitment: cc, end_date:)
    owner = if cc.present?
              cc
            elsif user_data["Portfolio Company"].present?
              investor = Investor.find_by(investor_name: user_data["Portfolio Company"])
              if user_data["Instrument"].present?
                instrument = investor.investment_instruments.find_by(name: user_data["Instrument"])
                instrument.aggregate_portfolio_investment.find_by(fund_id: @fund.id)
              else
                investor
              end
            else
              @fund
            end
    fund_ratio.value.should
    user_data["Value"].to_d
    fund_ratio.computation_context_id.should
    portfolio_scenario&.id
    fund_ratio.scenario.should
    user_data["Scenario"]&.strip
    fund_ratio.owner.should == owner
  end
end

Then('the FundRatios should be have owner from file {string}') do |file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    user_data = [headers, row].transpose.to_h
    # puts "Checking import of #{user_data}"
    folio_id = user_data["Folio No"]
    name = user_data["Ratio Name"]
    end_date = user_data["End Date"]
    end_date = end_date.is_a?(String) ? Date.local_parse(end_date) : nil
    portfolio_scenario_name = user_data["Portfolio Scenario"]
    portfolio_scenario = @fund.portfolio_scenarios.find_by(name: portfolio_scenario_name)

    cc = folio_id.present? ? @entity.capital_commitments.where(folio_id:).first : nil
    fund_ratio = FundRatio.find_by(name:, capital_commitment: cc, end_date:)
    owner = if folio_id.present?
              cc
            elsif user_data["Portfolio Company"].present?
              investor = Investor.find_by(investor_name: user_data["Portfolio Company"])
              if user_data["Instrument"].present?
                instrument = investor.investment_instruments.find_by(name: user_data["Instrument"])
                instrument.aggregate_portfolio_investment.find_by(fund_id: @fund.id)
              else
                investor
              end
            else
              @fund
            end

    fund_ratio.value.should
    user_data["Value"].to_d
    fund_ratio.display_value.should
    if fund_ratio.name.include?("IRR") || ["XIRR", "Fund Utilization", "Gross Portfolio IRR"].include?(fund_ratio.name)
      "#{user_data['Value'].to_d.to_f.round(2)} %"
    else
      "#{user_data['Value'].to_d.to_f.round(2)} x"
    end
    if portfolio_scenario.present?
      expect(fund_ratio.computation_context_id).to eq(portfolio_scenario.id)
      expect(fund_ratio.computation_context_type).to eq("PortfolioScenario")
    end
    user_data["Scenario"].present? ? user_data["Scenario"].strip : "Default"
    fund_ratio.scenario.should
    fund_ratio.end_date.should
    fund_ratio.owner.should == owner
  end
end

Then('all FundRatios for the fund should have latest set to true') do
  # After the first import there are no older records to compete with,
  # so every imported ratio must be flagged as latest.
  ratios = FundRatio.where(fund: @fund)
  expect(ratios.count).to be > 0
  expect(ratios.where(latest: false).count).to eq(0)
end

Then('only FundRatios with end date {string} should have latest set to true for the fund') do |end_date_str|
  # After importing a newer batch, only the records with the newer end_date
  # should carry latest=true; older records must have been demoted to false.
  end_date = Date.local_parse(end_date_str)
  newer_ratios = FundRatio.where(fund: @fund, end_date: end_date)
  older_ratios = FundRatio.where(fund: @fund).where.not(end_date: end_date)

  expect(newer_ratios.count).to be > 0
  expect(older_ratios.count).to be > 0

  # All newer records that share a name+scenario with an older record must be latest
  newer_ratios.each { |fr| expect(fr.latest).to be(true), "Expected latest=true for #{fr.name} end_date=#{fr.end_date}" }
  # Older records for the same name+scenario must have been demoted
  older_ratios.each { |fr| expect(fr.latest).to be(false), "Expected latest=false for #{fr.name} end_date=#{fr.end_date}" }
end

Given('I go to fund ratio show page') do
  @fund_ratio ||= FundRatio.last
  visit(fund_ratio_path(@fund_ratio))
end

Given('I fill the fund ratio form with {string}') do |args|
  @temp_ratio = FundRatio.new
  key_values(@temp_ratio, args)
  puts "Updating Fund Ratio #{@fund_ratio} - #{@fund_ratio.id} with values #{@temp_ratio.inspect}"
  fill_in("fund_ratio_scenario", with: @temp_ratio.scenario) if @temp_ratio.scenario.present?
  fill_in("fund_ratio_name", with: @temp_ratio.name) if @temp_ratio.name.present?
  fill_in("fund_ratio_value", with: @temp_ratio.value) if @temp_ratio.value.present?
  fill_in("fund_ratio_display_value", with: @temp_ratio.display_value) if @temp_ratio.display_value.present?
  fill_in("fund_ratio_end_date", with: Date.local_parse(@temp_ratio.end_date)) if @temp_ratio.end_date.present?
  fill_in("fund_ratio_label", with: @temp_ratio.label) if @temp_ratio.label.present?
  fill_in("fund_ratio_notes", with: @temp_ratio.notes) if @temp_ratio.notes.present?
end

Then('the FundRatio should be updated with correct data') do
  expect(page).to have_content("Fund ratio was successfully updated.")
  @fund_ratio.reload
  puts "Verifying Fund Ratio #{@fund_ratio} - #{@fund_ratio.id} values"
  puts "#{@fund_ratio.inspect}"
  expect(@fund_ratio.scenario).to eq(@temp_ratio.scenario) if @temp_ratio.scenario.present?
  expect(@fund_ratio.name).to eq(@temp_ratio.name) if @temp_ratio.name.present?
  expect(@fund_ratio.value).to eq(@temp_ratio.value) if @temp_ratio.value.present?
  expect(@fund_ratio.display_value).to eq(@temp_ratio.display_value) if @temp_ratio.display_value.present?
  expect(@fund_ratio.end_date).to eq(@temp_ratio.end_date) if @temp_ratio.end_date.present?
  expect(@fund_ratio.label).to eq(@temp_ratio.label) if @temp_ratio.label.present?
  expect(@fund_ratio.notes).to eq(@temp_ratio.notes) if @temp_ratio.notes.present?
end

Then('the fund ratio should have a {string} audit trail entry') do |action|
  @fund_ratio ||= FundRatio.last
  expect(@fund_ratio.audits.map(&:action)).to include(action)
end

When('the fund ratio notes is updated to {string}') do |notes|
  @fund_ratio ||= FundRatio.last
  @fund_ratio.update!(notes:)
end

Then('the fund ratio should have an {string} audit trail entry for {string}') do |action, field|
  @fund_ratio.reload
  audit = @fund_ratio.audits.where(action:).last
  expect(audit).not_to be_nil
  expect(audit.audited_changes.keys).to include(field)
end

When('I bulk delete all fund ratios for the fund via the UI') do
  @fund_ratio_ids = @fund.fund_ratios.pluck(:id)
  visit(fund_ratios_path(fund_id: @fund.id, q: { s: "id asc" }))
  find("#fund_ratio_bulk_actions").click
  click_on("Delete")
  click_on("Proceed")
  sleep(2)
end

Then('all fund ratios for the fund should be soft deleted with a {string} audit trail entry') do |action|
  expect(@fund_ratio_ids).not_to be_empty
  @fund_ratio_ids.each do |id|
    # default (paranoia) scope excludes soft-deleted rows; with_deleted bypasses it to verify the row still exists
    fr = FundRatio.with_deleted.find(id)
    expect(fr.deleted_at).not_to be_nil
    expect(FundRatio.where(id:).count).to eq(0)
    expect(fr.audits.map(&:action)).to include(action)
  end
end

Then('the cashflow CSV documents should be created for the fund ratios') do
  # We expect XIRR and MOIC ratios to have cashflow documents since return_cash_flows was true
  ratios_with_cf = FundRatio.where(name: ['XIRR', 'MOIC', 'Gross Portfolio IRR', 'IRR'])
  expect(ratios_with_cf.count).to be > 0

  ratios_with_cf.each do |fr|
    expect(fr.documents.count).to be >= 1
    doc = fr.documents.first
    expect(doc.name).to include("Cash Flows")
    expect(doc.file.metadata['filename']).to include(".csv")

    # Verify folder
    expect(doc.folder.name).to eq("FundRatios")
    expect(doc.folder.parent.name).to eq(@fund.name)
  end
end


Given('the fund has {string} Fund Formulas') do |count|
  (1..count.to_i).each do |i|
    ff = FactoryBot.create(:fund_formula, fund: @fund, entity_id: @fund.entity_id)
    puts "\n####FundFormula####\n"
    puts ff.to_json
  end
end

Given('the fund has fund ratios') do
    FundRatiosJob.perform_now(@fund.id, nil, Time.zone.now + 2.days, @user.id, true, return_cash_flows: true)
end

Given('Given I upload fund formulas update only sheet for the fund') do
  visit(fund_url(@fund))
  click_on("Actions")
  menu = find('#basic_reports', text: "Account Entries")  # Replace with actual selector
  menu.hover
  click_on("Allocation Formulas")
  sleep(1)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Fund Formulas Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/fund_formulas_update_only.xlsx"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should == 0
  ImportUpload.last.status.should == "Completed"
end

Given('Given I upload fund formulas for the fund') do
  @user.add_role :support # only support user can upload fund formulas
  @user.save!
  visit(fund_url(@fund))
  click_on("Actions")
  menu = find('#basic_reports', text: "Account Entries")  # Replace with actual selector
  menu.hover
  click_on("Allocation Formulas")
  sleep(1)
  click_on("Upload")
  sleep(2)
  fill_in('import_upload_name', with: "Test Fund Formulas Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/fund_formulas.xlsx"), make_visible: true)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  ImportUpload.last.failed_row_count.should == 0
  ImportUpload.last.status.should == "Completed"
end

Then('There should be {string} fund formulas created') do |string|
  @import_upload = ImportUpload.last
  expect(FundFormula.where(import_upload_id: @import_upload.id).count).to eq(string.to_i)
end

Then('the fund formulas must have the data in the sheet') do
  ffs = FundFormula.where(import_upload_id: @import_upload.id).order(:sequence).to_a
  file = File.open("./public/sample_uploads/fund_formulas.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    ff = ffs[idx-1]
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    ff.fund.should == @fund
    ff.name.should == user_data["Name"]
    ff.rule_for.should == user_data["Rule For"]
    ff.description.should == user_data["Description"]
    ff.generate_ytd_qtly.should == (user_data["Generate Ytd, Quarterly, Since Inception Numbers"]&.downcase == "yes")
    ff.tag_list.should == user_data["Tag List"].split(",").map(&:strip)
    ff.rule_type.should == user_data["Rule Type"]
    ff.formula.should == user_data["Formula"]
  end
end

Then('the fund formulas must have the data in the update only sheet') do
  file = File.open("./public/sample_uploads/fund_formulas_update_only.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    ff = @fund.fund_formulas.find(user_data['Id'])
    p "VALIDATING FUND FORMULA #{ff.id}"
    p [ff.id, ff.sequence, ff.name]

    ff.name.should == user_data["Name"]
    ff.rule_for.should == user_data["Rule For"]
    ff.description.should == user_data["Description"]
    ff.generate_ytd_qtly.should == (user_data["Generate Ytd, Quarterly, Since Inception Numbers"]&.downcase == "yes")
    ff.tag_list.should == user_data["Tag List"].split(",").map(&:strip)
    ff.rule_type.should == user_data["Rule Type"]
    ff.formula.should == user_data["Formula"]
    ff.meta_data.should == user_data["Metadata"]
    ff.enabled.should == (user_data["Enabled"]&.downcase == "yes")
    ff.roll_up.should == (user_data["Rollup"]&.downcase == "yes")
    ff.sequence.should == user_data["Sequence"].to_i
  end
end


Given('the fund has {string} Fund Ratios') do |count|
  (1..count.to_i).each do |i|
    fr = FactoryBot.create(:fund_ratio, fund: @fund, entity_id: @fund.entity_id)
    puts "\n####FundRatio####\n"
    puts fr.to_json
  end
end

Given('The fund has kyc level data generation enabled') do
  @fund ||= Fund.last
  @fund.json_fields["call_notice_on"] = "kyc"
  @fund.save!
end

  # Given the second commitment of the kyc has custom_fields "skip_doc_gen:true"
Given('the second commitment of the kyc has custom_fields {string}') do |custom_fields|
  InvestorKyc.all.each do |kyc|
    kyc.capital_commitments.where(fund: @fund).each_with_index do |cc, index|
      next unless index == 1 # only update the second commitment

      custom_fields.split(",").each do |pair|
        key, value = pair.split(":").map(&:strip)
        cc.json_fields[key] = value
      end
      cc.save!
    end
  end
end

Given('the KYC has commitments in different funds also') do
  @fund2 ||= Fund.create!(entity: @entity, name: "Second Fund", currency: @fund.currency, unit_types: @fund.unit_types)
  @fund.capital_commitments.each do |cc|
    CapitalCommitment.create!(entity: cc.entity, fund: @fund2, investor: cc.investor, investor_kyc: cc.investor_kyc, committed_amount_cents: cc.committed_amount_cents, commitment_date: cc.commitment_date, folio_id: "#{cc.folio_id}-2", fund_close: cc.fund_close)
  end
end

Then('KYC ratios must be computed for the commitments except for commitment with skip_doc_gen') do
  @fund.capital_commitments.each do |cc|
    puts "Commitment #{cc.id}  - ratios - #{FundRatio.where(capital_commitment_id: cc.id).pluck(:name)}"
    puts "Commitment json fields: #{cc.json_fields}"
    puts "-----------------------------------------------------------------------------"
    if cc.json_fields["skip_doc_gen"] == "yes"
      expect(FundRatio.where(capital_commitment_id: cc.id).count).to be_zero
    else
      comm_ratios = FundRatio.where(capital_commitment_id: cc.id)
      expect(comm_ratios.count).to_not be_zero
      comm_ratios.each do |fr|
        puts "ratio #{fr.id} #{fr.name} : owner - #{fr.owner_type} #{fr.owner_id} - #{fr  .owner.to_s}"
        expect(fr.owner == cc.investor_kyc).to eq(true)
      end
    end
  end
end
