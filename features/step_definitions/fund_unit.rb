Given('the fund has Fund Unit Settings') do
  @fund.unit_types.split(",").each do |unit_type|
    fus = FactoryBot.create(:fund_unit_setting, fund: @fund, name: unit_type.strip, entity_id: @fund.entity_id)
    puts "\n####FundUnitSetting####\n"
    puts fus.to_json
  end
end

Given('the fund has Fund Units') do
  @fund.capital_commitments.each do |cc|
    fu = FactoryBot.create(:fund_unit, capital_commitment: cc, fund_id: cc.fund_id, entity_id: @fund.entity_id, investor_id: cc.investor_id)
    puts "\n####FundUnit####\n"
    puts fu.to_json
  end
end

Given('the units are generated') do
  puts "### Generating units"
  puts "Before: FundUnit.count = #{FundUnit.count}, #{FundUnit.all.pluck(:id, :owner_id, :owner_type, :quantity, :unit_type, :price_cents)}"
  CapitalCall.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalCall", "Allocation for collected call amount", User.first.id)
  end
  CapitalDistribution.all.each do |cc|
    FundUnitsJob.perform_now(cc.id, "CapitalDistribution", "Redemption for distribution", User.first.id)
  end
  puts "After: FundUnit.count = #{FundUnit.count}, #{FundUnit.all.pluck(:id, :owner_id, :owner_type, :quantity, :unit_type, :price_cents)}"
end

Then('there should be correct units for the calls payment for each investor') do
  FundUnit.count.should == CapitalCommitment.count * CapitalCall.count
  CapitalCommitment.all.each do |cc|
    puts "Checking units for #{cc}"
    cc.fund_units.length.should > 0
    cc.fund_units.each do |fu|
      ap fu
      fu.unit_type.should == cc.unit_type
      fu.owner_type.should == "CapitalRemittance"

      capital_remittance = fu.owner
      fu.price_cents.should == fu.owner.capital_call.unit_prices[fu.unit_type]["price"].to_d * 100.0

      if capital_remittance.collected_amount_cents >= capital_remittance.call_amount_cents
        amount_cents = capital_remittance.call_amount_cents # - capital_remittance.allocated_unit_amount_cents
      else
        amount_cents = capital_remittance.collected_amount_cents # - capital_remittance.allocated_unit_amount_cents
      end

      fu.amount_cents.should == amount_cents
      fu.quantity.round(2).should == ( amount_cents / (fu.price_cents + fu.premium_cents)).round(2)
    end
  end
end

Given('Given I upload a fund unit settings {string} for the fund') do |file_name|
  visit(fund_url(@fund))
  click_on("Actions")
  click_on("Fund Unit Settings")
  sleep(1)
  click_on("Upload")
  #sleep((6)
  fill_in('import_upload_name', with: "Test Fund Unit Settings Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
  ImportUpload.last.status.should == "Completed"
end

Then('There should be {string} fund unit settings created with data in {string}') do |count, file_name|
  FundUnitSetting.all.count.should == count.to_i

  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
  custom_field_headers = headers - ImportFundUnitSetting::STANDARD_HEADERS
  fund_unit_settings = FundUnitSetting.all.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    fus = fund_unit_settings[idx-1]
    puts "Checking import of #{fus.to_json}"

    fus.fund_id.should == Fund.find_by(name: row_data["Fund"]).id
    fus.name.should == row_data["Class/Series"]
    fus.management_fee.should == row_data["Management Fee %"]
    fus.setup_fee.should == row_data["Setup Fee %"]
    fus.gp_units.should == row_data["Gp Units"].strip.casecmp?("Yes")
    fus.carry.should == row_data["Carry %"]
    fus.isin.should == row_data["Isin"]

    # Check that the custom fields got imported
    custom_field_headers.each do |cf_header|
      puts "Checking custom field #{cf_header}"
      cf_name = FormCustomField.to_name(cf_header)
      fus.custom_fields[cf_name].to_s.should == row_data[cf_header].to_s.strip

      fcf = FormCustomField.where(name: cf_name).first
      puts "Checking custom field #{fcf.name}"
      fcf.should be_present
    end

  end
end

Then('Given I upload {string} file for Fund Units of the fund') do |file_name|
  visit(fund_units_url)
  #sleep((2)
  click_on("Upload")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Fund Units Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file_name}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == 0
  # status is nil when no errors
  ImportUpload.last.status.should == "Completed"
end

Then('There should be {string} fund units created with data in the sheet') do |count|
  file = File.open("./public/sample_uploads/fund_units.xlsx", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_commitment = CapitalCommitment.where(folio_id: row_data["Folio No"]).first

    fund_unit = FundUnit.where(capital_commitment_id: capital_commitment.id, quantity: row_data["Quantity"].to_f).first

    puts "Checking import of #{fund_unit.to_json}"

    fund_unit.quantity.should == row_data["Quantity"].to_f
    fund_unit.unit_type.should == row_data["Unit Type"]
    fund_unit.price_cents.should == row_data["Price"].to_f * 100.0
    fund_unit.premium_cents.should == row_data["Premium"].to_f * 100.0
    fund_unit.issue_date.should == Date.local_parse(row_data["Issue Date"])
    fund_unit.reason.should == row_data["Reason"]
    fund_unit.owner.folio_id.should == row_data["Folio No"].to_s

    if fund_unit.quantity.positive?
      fund_unit.owner_type.should == "CapitalRemittance"
    else
      fund_unit.owner_type.should == "CapitalDistributionPayment"
    end
  end
end

When('fund units are transferred {string}') do |transfer|

  @fund.reload
  @price, @premium, @transfer_ratio, @transfer_account_entries, @account_entries_excluded = transfer.split(",").map{|x| x.split("=")[1]}
  @price = @price.to_f
  @premium = @premium.to_f
  @transfer_ratio = @transfer_ratio.to_f
  @transfer_account_entries = @transfer_account_entries == "true"

  @from_cc = @fund.capital_commitments.first
  @from_cc_committed_amount_cents = @from_cc.committed_amount_cents
  @from_cc_folio_committed_amount_cents = @from_cc.folio_committed_amount_cents

  @to_cc = @fund.capital_commitments.last
  @to_cc_committed_amount_cents = @to_cc.committed_amount_cents
  @to_cc_folio_committed_amount_cents = @to_cc.folio_committed_amount_cents
  @transfer_quantity = (@transfer_ratio * @from_cc.total_fund_units_quantity).to_f

  @transfer = FundUnitTransfer.create(entity_id: @from_cc.entity_id, from_commitment: @from_cc, to_commitment: @to_cc, fund: @fund, price: @price, premium: @premium, transfer_ratio: @transfer_ratio * 100, transfer_date: Date.today, transfer_account_entries: @transfer_account_entries, account_entries_excluded: @account_entries_excluded)

  result = FundUnitTransferService.wtf?(transfer: @transfer)

  puts result[:error]
  result.success?.should == true
  @transfer_token = result[:transfer_token]
end

When('fund units are transferred {string} and from_commitment has attrs {string} and to_commitment has attrs {string}') do |transfer, from_comm_attrs, to_comm_attrs|
  @fund = Fund.first
  @fund.reload
  @price, @premium, @transfer_ratio, @transfer_account_entries, @account_entries_excluded = transfer.split(",").map{|x| x.split("=")[1]}
  @price = @price.to_f
  @premium = @premium.to_f
  @transfer_ratio = @transfer_ratio.to_f
  @transfer_account_entries = @transfer_account_entries == "true"

  @from_cc = @fund.capital_commitments.first
  key_values(@from_cc, from_comm_attrs)
  @from_cc.save(validate: false)
  @from_cc_committed_amount_cents = @from_cc.committed_amount_cents
  @from_cc_folio_committed_amount_cents = @from_cc.folio_committed_amount_cents

  @to_cc = @fund.capital_commitments.last
  key_values(@to_cc, to_comm_attrs)
  @to_cc.save(validate: false)
  @to_cc_committed_amount_cents = @to_cc.committed_amount_cents
  @to_cc_folio_committed_amount_cents = @to_cc.folio_committed_amount_cents
  @transfer_quantity = (@transfer_ratio * @from_cc.total_fund_units_quantity).to_f

  @transfer = FundUnitTransfer.create(entity_id: @from_cc.entity_id, from_commitment: @from_cc, to_commitment: @to_cc, fund: @fund, price: @price, premium: @premium, transfer_ratio: @transfer_ratio * 100, transfer_date: Date.today, transfer_account_entries: @transfer_account_entries, account_entries_excluded: @account_entries_excluded)

  @result = FundUnitTransferService.wtf?(transfer: @transfer)

  puts @result[:error]
end

Then('the units should be transferred') do

  from_fu = @from_cc.fund_units.last
  to_fu = @to_cc.fund_units.last

  from_fu.quantity.should == -@transfer_quantity
  from_fu.price_cents.should == @price * 100
  from_fu.premium_cents.should == @premium * 100
  from_fu.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  to_fu.quantity.should == @transfer_quantity
  to_fu.price_cents.should == @price * 100
  to_fu.premium_cents.should == @premium * 100
  to_fu.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true


  @transfer.reload
  @transfer.status.should == "completed"


  @from_cc.reload
  @from_cc.committed_amount_cents.should == @from_cc_committed_amount_cents * (1 - @transfer_ratio)

end

Then('I should be able to see the transferred fund units') do
  @from_cc = @fund.capital_commitments.first
  @to_cc = @fund.capital_commitments.last
  from_fu = @from_cc.fund_units.last
  to_fu = @to_cc.fund_units.last

  visit(fund_unit_path(from_fu))
  expect(page).to have_content(number_with_delimiter(from_fu.quantity))
  expect(page).to have_content(money_to_currency(from_fu.price))
  expect(page).to have_content(money_to_currency(from_fu.premium))
  expect(page).to have_content(from_fu.reason)
  expect(page).to have_content(from_fu.transfer&.titleize)


  visit(fund_unit_path(to_fu))
  expect(page).to have_content(number_with_delimiter(to_fu.quantity))
  expect(page).to have_content(money_to_currency(to_fu.price))
  expect(page).to have_content(money_to_currency(to_fu.premium))
  expect(page).to have_content(to_fu.reason)
  expect(page).to have_content(to_fu.transfer&.titleize)
end

When('fund units are transferred with ratio percentage {int}') do |ratio_pct|
  @fund.reload
  @from_cc = @fund.capital_commitments.first
  @to_cc   = @fund.capital_commitments.last

  transfer = FundUnitTransfer.new(
    entity_id:               @from_cc.entity_id,
    from_commitment:         @from_cc,
    to_commitment:           @to_cc,
    fund:                    @fund,
    price:                   100.0,
    premium:                 0.0,
    transfer_ratio:          ratio_pct,
    transfer_date:           Date.today,
    transfer_account_entries: false
  )
  @result = FundUnitTransferService.wtf?(transfer:)
end

Given('the fund units are fully transferred') do
  @fund.reload
  @from_cc = @fund.capital_commitments.first
  @to_cc   = @fund.capital_commitments.last

  transfer = FundUnitTransfer.create!(
    entity_id:               @from_cc.entity_id,
    from_commitment:         @from_cc,
    to_commitment:           @to_cc,
    fund:                    @fund,
    price:                   100.0,
    premium:                 0.0,
    transfer_ratio:          100,
    transfer_date:           Date.today,
    transfer_account_entries: false
  )
  FundUnitTransferService.call(transfer:)
  @from_cc.reload
end

When('the fund units are transferred excluding the first account entry') do
  @fund.reload
  @transfer_ratio = 0.5

  # Account entries are optional on a commitment; find one that is actually
  # linked so we have something concrete to exclude from pro-rating.
  @excluded_ae = @fund.account_entries.where.not(capital_commitment_id: nil).first
  raise "No commitment-linked account entries in fund — check fixture data" if @excluded_ae.nil?

  @from_cc = @excluded_ae.capital_commitment
  # to_commitment must share the same unit_type and have a commitment_date on or
  # before from_commitment's date (both conditions enforced by validate_transfer).
  @to_cc = @fund.capital_commitments
                 .where(unit_type: @from_cc.unit_type)
                 .where.not(id: @from_cc.id)
                 .where("commitment_date <= ?", @from_cc.commitment_date)
                 .first
  raise "No suitable to_commitment found — need same unit_type and earlier/equal commitment_date" if @to_cc.nil?

  @from_cc_folio_committed_amount_cents = @from_cc.folio_committed_amount_cents
  @transfer_quantity = (@transfer_ratio * @from_cc.total_fund_units_quantity).to_f
  @excluded_ae_name        = @excluded_ae.name
  @excluded_ae_orig_amount = @excluded_ae.amount_cents

  transfer = FundUnitTransfer.create!(
    entity_id:                @from_cc.entity_id,
    from_commitment:          @from_cc,
    to_commitment:            @to_cc,
    fund:                     @fund,
    price:                    1000.0,
    premium:                  100.0,
    transfer_ratio:           (@transfer_ratio * 100).to_i,
    transfer_date:            Date.today,
    transfer_account_entries: true,
    account_entries_excluded: @excluded_ae_name
  )
  result = FundUnitTransferService.wtf?(transfer:)
  puts result[:error]
  result.success?.should == true
  @transfer_token = result[:transfer_token]
end

Then('the excluded account entry is copied in full to the to commitment') do
  @excluded_ae.reload
  # Service rounds to 2 decimal places; compare at that precision.
  @excluded_ae.amount_cents.round(2).should == @excluded_ae_orig_amount.round(2)

  to_entry = @to_cc.account_entries.detect { |e| e.json_fields["transfer_id"] == @transfer_token && e.name == @excluded_ae_name }
  to_entry.should_not be_nil
  to_entry.amount_cents.round(2).should == @excluded_ae_orig_amount.round(2)
  to_entry.investor_id.should  == @to_cc.investor_id
  to_entry.folio_id.should     == @to_cc.folio_id
end

Then('the fund unit counter caches are correct after transfer') do
  @from_cc.reload
  @to_cc.reload

  from_actual = @from_cc.fund_units.sum(:quantity)
  to_actual   = @to_cc.fund_units.sum(:quantity)

  @from_cc.total_fund_units_quantity.to_d.should be_within(BigDecimal("0.01")).of(from_actual.to_d)
  @to_cc.total_fund_units_quantity.to_d.should   be_within(BigDecimal("0.01")).of(to_actual.to_d)
end

Then('there should be correct units generated for the latest payment') do
  @fund.capital_remittances.each do |cr|
    fund_unit = cr.fund_units.last
    crp = cr.capital_remittance_payments.last
    puts "Checking fund unit for #{cr.id} with fund unit id #{fund_unit.id} amount #{fund_unit.amount} against payment #{crp.id} amount #{crp.amount}"
    fund_unit.amount.should == crp.amount
  end
end

Then('the total units should match the total paid amount') do
  @fund.capital_remittances.each do |cr|
    total_paid = cr.capital_remittance_payments.sum(&:amount)
    total_units = cr.fund_units.sum(&:amount)
    puts "Checking total paid #{total_paid} against total units amount #{total_units}"
    total_paid.should == total_units
  end
end

Then('the total units should be {string}') do |count|
  FundUnit.count.should == count.to_i
end

Then('I can fetch the fund unit setting associated with the commitments') do
  commitment_investors_fund_unit_settings = {
    "Investor 1" => "Series A",
    "Investor 2" => "Series A",
    "Investor 3" => "Series B",
    "Investor 4" => "Series B",
    "Investor 5" => "Series C",
    "Investor 6" => "Series D",
  }
  @fund.capital_commitments.each do |cc|
    expect(cc.fund_unit_setting).to be_present
    expect(cc.fund_unit_setting.name).to eq(cc.unit_type)
    expect(cc.fund_unit_setting.name).to eq(commitment_investors_fund_unit_settings[cc.investor_name])
  end
end

Then('There should be {string} fund units created with data in the {string} sheet') do |count, file_name|
  file = File.open("./public/sample_uploads/#{file_name}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    row_data = [headers, row].transpose.to_h
    capital_commitment = CapitalCommitment.where(folio_id: row_data["Folio No"]).first

    fund_unit = FundUnit.where(capital_commitment_id: capital_commitment.id, quantity: row_data["Quantity"].to_f).first

    puts "Checking import of #{fund_unit.to_json}"

    fund_unit.quantity.should == row_data["Quantity"].to_f
    fund_unit.unit_type.should == row_data["Unit Type"]
    fund_unit.price_cents.should == row_data["Price"].to_f * 100.0
    fund_unit.premium_cents.should == row_data["Premium"].to_f * 100.0
    fund_unit.issue_date.should == Date.local_parse(row_data["Issue Date"])
    fund_unit.reason.should == row_data["Reason"]
    fund_unit.owner.folio_id.should == row_data["Folio No"].to_s

    if fund_unit.quantity.positive?
      fund_unit.owner_type.should == "CapitalRemittance"
    else
      fund_unit.owner_type.should == "CapitalDistributionPayment"
    end
  end
end


Then('the remittances are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.capital_remittances.each do |cr|
    if cr.json_fields["transfer_id"].present?
      puts "Checking capital remittance for #{cr.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cr.json_fields["transfer_id"].should == @transfer_token
      # cr.json_fields["orig_call_amount"].should == cr.call_amount_cents / retained_ratio
      cr.call_amount_cents.should == (cr.json_fields["orig_call_amount"].to_f * retained_ratio).round
      # cr.json_fields["orig_collected_amount"].should == cr.collected_amount_cents / retained_ratio
      cr.collected_amount_cents.should == (cr.json_fields["orig_collected_amount"].to_f * retained_ratio).round

      cr.capital_remittance_payments.each do |crp|
        puts "Checking capital remittance payment for #{crp.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
        crp.json_fields["transfer_id"].should == @transfer_token
        # crp.json_fields["orig_amount"].should == crp.amount_cents / retained_ratio
        crp.amount_cents.should == (crp.json_fields["orig_amount"].to_f * retained_ratio).round
      end
    end
  end

  @to_cc.capital_remittances.each do |cr|
    cr.reload # Ensure the latest data is loaded from the database

    if cr.json_fields["transfer_id"].present?
      puts "Checking capital remittance for #{cr.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"

      cr.investor_id.should == @to_cc.investor_id
      cr.folio_id.should == @to_cc.folio_id
      cr.investor_name.should == @to_cc.investor_name
      cr.json_fields["transfer_id"].should == @transfer_token
      # cr.json_fields["orig_call_amount"].should == cr.call_amount_cents / transfer_ratio
      cr.call_amount_cents.should == (cr.json_fields["orig_call_amount"].to_f * transfer_ratio).round
      # cr.json_fields["orig_collected_amount"].should == cr.collected_amount_cents / transfer_ratio
      cr.collected_amount_cents.should == (cr.json_fields["orig_collected_amount"].to_f * transfer_ratio).round

      cr.capital_remittance_payments.each do |crp|
        puts "Checking capital remittance payment for #{crp.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
        crp.json_fields["transfer_id"].should == @transfer_token
        # crp.json_fields["orig_amount"].should == crp.amount_cents / transfer_ratio
        crp.amount_cents.should == (crp.json_fields["orig_amount"].to_f * transfer_ratio).round
      end
    end
  end
end

Then('distributions are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.capital_distribution_payments.each do |cdp|
    if cdp.json_fields["transfer_id"].present?
      puts "Checking capital distribution payment for #{cdp.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cdp.json_fields["transfer_id"].should == @transfer_token
      # cdp.json_fields["orig_gross_payable"].should == cdp.gross_payable_cents / retained_ratio
      cdp.gross_payable_cents.round(0).should == (cdp.json_fields["orig_gross_payable"].to_f * retained_ratio).round(0)
      # cdp.json_fields["orig_units_quantity"].should == cdp.units_quantity / retained_ratio
      cdp.units_quantity.round(0).should == (cdp.json_fields["orig_units_quantity"].to_f * retained_ratio).round(0)
    end
  end

  @to_cc.capital_distribution_payments.each do |cdp|
    if cdp.json_fields["transfer_id"].present?
      puts "Checking capital distribution payment for #{cdp.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
      cdp.json_fields["transfer_id"].should == @transfer_token
      cdp.investor_id.should == @to_cc.investor_id
      # cdp.json_fields["orig_gross_payable"].should == cdp.gross_payable_cents / transfer_ratio
      cdp.gross_payable_cents.round(0).should == (cdp.json_fields["orig_gross_payable"].to_f * transfer_ratio).round(0)
      # cdp.json_fields["orig_units_quantity"].should == cdp.units_quantity / transfer_ratio
      cdp.units_quantity.round(0).should == (cdp.json_fields["orig_units_quantity"].to_f * transfer_ratio).round(0)
    end
  end
end

Then('adjustments are create upon fund unit transfer') do

  transfer_ratio = @transfer_ratio

  from_adjustment = @from_cc.commitment_adjustments.where(adjustment_type: "Transfer").last
  to_adjustment = @to_cc.commitment_adjustments.where(adjustment_type: "Transfer").last

  puts "Checking commitment adjustment for #{from_adjustment.id} for #{@from_cc.folio_id}"
  from_adjustment.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  # from_adjustment.amount_cents.should == -(@from_cc_committed_amount_cents * transfer_ratio).round
  from_adjustment.folio_amount_cents.should == -(@from_cc_folio_committed_amount_cents * transfer_ratio).round
  from_adjustment.adjustment_type.should == "Transfer"
  from_adjustment.as_of.should == @from_cc.commitment_date
  from_adjustment.transfer_date.should == @transfer.transfer_date

  puts "Checking commitment adjustment for #{to_adjustment.id} for #{@to_cc.folio_id}"
  to_adjustment.reason.include?("Transfer from #{@from_cc.folio_id} to #{@to_cc.folio_id}").should == true
  # to_adjustment.amount_cents.should == (@from_cc_committed_amount_cents * transfer_ratio).round
  to_adjustment.folio_amount_cents.should == (@from_cc_folio_committed_amount_cents * transfer_ratio).round
  to_adjustment.adjustment_type.should == "Transfer"
  to_adjustment.as_of.should == @from_cc.commitment_date
  to_adjustment.transfer_date.should == @transfer.transfer_date
end

Given('the fund has {int} fund units of type {string}') do |count, unit_type|
  create_fund_units_for_pagination(count, unit_type)
end

Given('the fund has {int} fund units of type {string} with reason {string}') do |count, unit_type, reason|
  create_fund_units_for_pagination(count, unit_type, reason:)
end

Given('the fund has an old fund unit with reason {string}') do |reason|
  create_fund_units_for_pagination(1, "A", reason:, issue_date: Date.new(2020, 1, 1))
end

Given('the fund units have increasing quantities') do
  FundUnit.order(:id).each_with_index { |fund_unit, index| fund_unit.update_columns(quantity: index + 1) }
end

When('I open the fund units list') do
  visit(fund_units_url)
end

When('I open the fund units list with {string}') do |query|
  visit("#{fund_units_url}?#{query}")
end

Given('the fund units belong to an import upload') do
  @import_upload = ImportUpload.create!(entity: @fund.entity, owner: @fund, import_type: "FundUnit", name: "Fund units import",
                                        user_id: @user.id, status: "Completed",
                                        import_file: File.open(File.absolute_path("./public/sample_uploads/fund_units.xlsx")))
  FundUnit.where(fund_id: @fund.id).update_all(import_upload_id: @import_upload.id)
end

When('I open the import upload page') do
  visit(import_upload_url(@import_upload))
  page.execute_script("document.getElementById('fund_units_frame').scrollIntoView()")
end

When('I open the investor page with the fund units section') do
  @fund_units_investor = @fund.capital_commitments.first.investor
  visit(investor_url(@fund_units_investor))
  open_tab_pane('fund-units-tab') # under the stakeholder page's Commitments dropdown
end

Then('I should still be on the investor page') do
  expect(page).to have_current_path(investor_path(@fund_units_investor))
end

When('I click the fund units page link {string}') do |label|
  within(".pagination") { click_on(label, exact: true) }
end

Then('I should see {int} fund unit rows') do |count|
  expect(page).to have_css("table#fund_units tbody tr", count:)
end

Then('I should see the fund units pager text {string}') do |text|
  # pagy_info renders ranges with a non-breaking hyphen (U+2011)
  expect(page.text.tr("\u2011", "-")).to include(text)
end

Then('I should not see a fund units pager') do
  expect(page).not_to have_css(".pagination")
  expect(page).not_to have_content("Showing")
end

Then('I should not see fund units page links') do
  expect(page).not_to have_css(".pagination")
end

Then('I should see exactly one fund units pager') do
  expect(page).to have_css(".pagination", count: 1)
  expect(page).not_to have_css(".dataTables_paginate")
end

Then('the fund units should be listed by latest issue date first') do
  row_ids = page.all("table#fund_units tbody tr").map { |tr| tr[:id] }
  expected = FundUnit.order(issue_date: :desc, id: :desc).limit(row_ids.size).map { |fu| "fund_unit_#{fu.id}" }
  expect(row_ids).to eq(expected)
end

Then('the fund units download should contain {int} unit rows') do |count|
  b64 = page.evaluate_async_script(<<~JS, "/fund_units.xlsx?all=true")
    var url = arguments[0];
    var done = arguments[arguments.length - 1];
    fetch(url, { credentials: "same-origin" })
      .then(function (r) { return r.arrayBuffer(); })
      .then(function (buf) {
        var bytes = new Uint8Array(buf);
        var bin = "";
        for (var i = 0; i < bytes.length; i++) { bin += String.fromCharCode(bytes[i]); }
        done(btoa(bin));
      });
  JS
  tmp = Tempfile.new(["fund_units", ".xlsx"], binmode: true)
  tmp.write(Base64.decode64(b64))
  tmp.close
  sheet = Roo::Spreadsheet.open(tmp.path, extension: :xlsx)
  (sheet.last_row - 1).should == count
end

When('I search the fund units list for {string}') do |text|
  find_field("search").send_keys(text, :enter)
end

When('I search the fund units section for {string}') do |text|
  within("div#fund_units") { find_field("search").send_keys(text, :enter) }
end

When('I sort the fund units list by {string}') do |label|
  within("table#fund_units thead") { click_on(label, exact: true) }
end

Then('I should see only fund units with reason {string}') do |reason|
  rows = page.all("table#fund_units tbody tr")
  expect(rows).not_to be_empty
  rows.each { |row| expect(row.text).to include(reason) }
end

Then('the fund unit rows should be ordered by quantity ascending') do
  # Quantity is the 4th column without cols=all: type, folio, issue date, quantity
  quantities = page.all("table#fund_units tbody tr").map { |row| row.all("td")[3].text.delete(",").to_f }
  expect(quantities).to eq(quantities.sort)
  expect(quantities.first).to eq(FundUnit.minimum(:quantity).to_f)
end

def create_fund_units_for_pagination(count, unit_type, reason: nil, issue_date: nil)
  commitment = @fund.capital_commitments.first
  @fund_unit_issue_date_offset ||= 0
  count.times do
    @fund_unit_issue_date_offset += 1
    attrs = { capital_commitment: commitment, fund_id: commitment.fund_id, entity_id: @fund.entity_id,
              investor_id: commitment.investor_id, unit_type:,
              issue_date: issue_date || (Date.new(2025, 1, 1) + @fund_unit_issue_date_offset.days) }
    attrs[:reason] = reason if reason
    FactoryBot.create(:fund_unit, **attrs)
  end
end
