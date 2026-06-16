When('I create a Capital Call with percentage of commitment') do
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Demo call'
	#sleep(1)
	fill_in "capital_call[close_percentages][First Close]", with: "10"
	fill_in "capital_call[close_percentages][Second Close]", with: "20"
  find('input[name="capital_call[call_date]"]').set('2024-09-13')
  find('input[name="capital_call[due_date]"]').set('2024-11-13')
  allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
  click_on('Save')
  expect(page).to have_content("Capital call was successfully")
end

When("I create a Capital Call with upload call basis") do
	allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Upload capital call'
	#sleep(1)
	select 'Upload', from: 'capital_call[call_basis]'
	fill_in 'Series A_price', with: '1'
	click_on('Save')
	expect(page).to have_content("Capital call was successfully")
end

When("I create a Capital Call with investable call basis") do
	visit("/funds/1")
	#sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	#sleep(0.2)
	click_on("New Call")
	#sleep(0.2)
	fill_in 'capital_call_name', with: 'Investable capital call'
	#sleep(1)
	select 'Investable Capital Percentage', from: 'capital_call[call_basis]'
	find('span.select2-selection--multiple').click
	find('ul.select2-results__options', visible: true)
	find('li.select2-results__option', text: 'Second Close').click
	click_on('Save')
	expect(page).to have_content("Capital call was successfully")
end

Given("it should create a Capital Call with given data") do
	capital_call = CapitalCall.last
	expect(capital_call.name).to(eq("Upload capital call"))
	expect(capital_call.call_basis).to(eq("Upload"))
	expect(capital_call.fund_closes).to_not be_present
end

Given("it should create a Investable Capital Call with given data") do
	capital_call = CapitalCall.last
	expect(capital_call.name).to(eq("Investable capital call"))
	expect(capital_call.call_basis).to(eq("Investable Capital Percentage"))
	expect(capital_call.fund_closes).to(eq(["Second Close"]))
end

Given("it should create Capital Remittances according to the close percentage") do
	expect(CapitalRemittance.pluck(:percentage)).to match_array([BigDecimal("10"), BigDecimal("20")])
end

Given('the remittances has some units already allocated') do
  capital_remittance = CapitalRemittance.last
  fund_unit = capital_remittance.fund_units.build(
    fund_id:capital_remittance.capital_commitment.fund_id,
    capital_commitment_id: capital_remittance.capital_commitment.id,
    investor_id: capital_remittance.capital_commitment.investor_id,
    entity_id: capital_remittance.entity_id,
    unit_type: capital_remittance.capital_commitment.unit_type,
    quantity: 10.0,
    price: 50.0,
    premium: 10.0,
    issue_date: Date.today,
    reason: "Initial Allocation"
  )
  fund_unit.save!

  @pending_amount_for_units_allocation, @reason = capital_remittance.pending_amount_for_units_allocation
  puts "Pending amount for units allocation: #{@pending_amount_for_units_allocation}"
  puts "Reason: #{@reason}"
end


Then('it should generate only the remaining units') do

	capital_remittance = CapitalRemittance.last
	fund_unit = capital_remittance.fund_units.last
	puts "Fund Unit: #{fund_unit.inspect}"
	expect(fund_unit).to be_present
	expect(fund_unit.amount.cents).to eq(@pending_amount_for_units_allocation)
	expect(fund_unit.reason).to include(@reason)

	# Ensure that the new fund unit is created
	capital_remittance.fund_units.count.should == 2
end


And("error email for fund units already allocated should be sent") do
	current_email = open_email(User.first.email)
	expect(current_email).to have_content("Fund Units already allocated")
end

Given('I delete a remittance with no payments') do
  CapitalRemittance.all.each do |cr|
		if cr.capital_remittance_payments.blank?
			@capital_remittance = cr
			break
		end
  end
	visit capital_remittance_path(@capital_remittance)
	click_on "Delete"
	click_on "Proceed"
end

Then('the remittance is successfully deleted') do
	expect(page).to have_content("Capital remittance was successfully destroyed")
end

Given('I delete a remittance having payments with allocated units') do
	CapitalRemittance.all.each do |cr|
		if cr.capital_remittance_payments.present?
			 cr.capital_remittance_payments.each do |payment|
				 if payment.units_already_allocated?
					 puts "Found a remittance with allocated units: #{cr.id}"
					 @capital_remittance = cr
					 break
				 end
			 end
		end
	end
	@user = User.first
	@user.add_role(:company_admin)
	visit capital_remittance_path(@capital_remittance)
	click_on "Delete"
	click_on "Proceed"
end

Then('I get the error {string}') do |string|
	expect(page).to have_content(string)
end



  Given('there is a capital call {string}') do |arg|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund, entity: @fund.entity)
    # Todo: Abhay Move this logic to env
    hash = arg.split('=').last
    hash = hash.gsub("'", "\"")
    close_percentages = JSON.parse(hash)
    if close_percentages.is_a?(Hash) && close_percentages.key?("First Close")
      @capital_call.close_percentages = close_percentages
    else
      key_values(@capital_call, arg)
    end
    CapitalCallCreate.call(capital_call: @capital_call)
    puts "\n####CapitalCall####\n"
    puts @capital_call.to_json
  end

  When('I create a new capital call {string}') do |args|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund)
    key_values(@capital_call, args)
    @capital_call.setup_defaults

    puts @capital_call.to_json

    visit(fund_url(@fund))

    click_on "Calls"
    click_on "New Call"

    fill_in('capital_call_name', with: @capital_call.name)

    fill_in('capital_call_due_date', with: @capital_call.due_date)
    # Field only renders when the fund has commitments with a matching fund_close
    if page.has_field?("capital_call[close_percentages][First Close]", wait: 0)
      fill_in "capital_call[close_percentages][First Close]", with: "50"
    end
    select(@capital_call.call_basis, from: 'capital_call_call_basis')

    if @capital_call.call_basis == "Percentage of Commitment"
      if page.has_field?("capital_call[close_percentages][First Close]", wait: 0)
        fill_in "capital_call[close_percentages][First Close]", with: @capital_call.percentage_called
      end
    elsif @capital_call.call_basis != "Upload"
      find('#select2-capital_call_fund_closes-container', visible: false)
      select2_trigger = find('.select2-selection--multiple', match: :first)
      select2_trigger.click
      first_option = find(".select2-results__option", match: :first, visible: true)
      first_option.click
      fill_in('capital_call_amount_to_be_called', with: @capital_call.amount_to_be_called)
    end

    if @fund.entity.permissions.enable_units?
      @fund.unit_types.split(",").each do |unit_type|
        unit_type = unit_type.strip
        fill_in("#{unit_type}_price", with: @capital_call.unit_prices[unit_type]["price"])
        fill_in("#{unit_type}_premium", with: @capital_call.unit_prices[unit_type]["premium"])
      end
    end

    if @capital_call.call_basis == "Amount allocated on Investable Capital"
      @capital_call.fee_account_entry_names.each_with_index do |fee_name, idx|
        click_on "Add Fees"
        #sleep((1)
        within all(".nested-fields").last do
          select(fee_name, from: "fee_name")
          fill_in("fee_start_date", with: Time.zone.today - 10.years)
          fill_in("fee_end_date", with: Time.zone.today)
          select(CapitalCall::FEE_TYPES[0], from: "call_fee_types")
        end
      end
    end
    allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
    click_on "Save"
    # sleep(2)
    expect(page).to have_content("Capital call was successfully")
  end

  When('I create a new capital call {string} with fees') do |args|
    @capital_call = FactoryBot.build(:capital_call, fund: @fund)
    key_values(@capital_call, args)
    @capital_call.setup_defaults

    puts @capital_call.to_json

    visit(fund_url(@fund))

    click_on "Calls"
    click_on "New Call"

    fill_in('capital_call_name', with: @capital_call.name)

    fill_in('capital_call_due_date', with: @capital_call.due_date)
    # Field only renders when the fund has commitments with a matching fund_close
    if page.has_field?("capital_call[close_percentages][First Close]", wait: 0)
      fill_in "capital_call[close_percentages][First Close]", with: "50"
    end
    select(@capital_call.call_basis, from: 'capital_call_call_basis')

    if @capital_call.call_basis == "Percentage of Commitment"
      if page.has_field?("capital_call[close_percentages][First Close]", wait: 0)
        fill_in "capital_call[close_percentages][First Close]", with: @capital_call.percentage_called
      end
    elsif @capital_call.call_basis != "Upload"
      find('#select2-capital_call_fund_closes-container', visible: false)
      select2_trigger = find('.select2-selection--multiple', match: :first)
      select2_trigger.click
      first_option = find(".select2-results__option", match: :first, visible: true)
      first_option.click
      fill_in('capital_call_amount_to_be_called', with: @capital_call.amount_to_be_called)
    end

    if @fund.entity.permissions.enable_units?
      @fund.unit_types.split(",").each do |unit_type|
        unit_type = unit_type.strip
        fill_in("#{unit_type}_price", with: @capital_call.unit_prices[unit_type]["price"])
        fill_in("#{unit_type}_premium", with: @capital_call.unit_prices[unit_type]["premium"])
      end
    end

    if (@capital_call.fee_account_entry_names - ["Other"]).present?
      (@capital_call.fee_account_entry_names - ["Other"]).each do |fee_name, idx|
        click_on "Add Fees"
        #sleep((1)
        within all(".nested-fields").last do
          select(fee_name, from: "fee_name")
          fill_in("fee_start_date", with: Time.zone.today - 10.years)
          fill_in("fee_end_date", with: Time.zone.today)
          select(CapitalCall::FEE_TYPES[0], from: "call_fee_types")
        end
      end
    end
    allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
    click_on "Save"
    # sleep(2)
    expect(page).to have_content("Capital call was successfully")
  end

  Then('The remittances should have the proper fees and call amount') do
    @capital_call.reload
    @remittance_fees = {}
    @remittance_call_amounts = {}
    if @capital_call.call_fees.present?
      @capital_call.capital_remittances.each_with_index do |remittance, idx|
        fees_cents = 0
        @capital_call.call_fees.each do |fee|
          fee_cents = remittance.capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", fee.start_date, fee.end_date, fee.name, false).sum(:amount_cents)
          puts "### Remittance #{remittance.id} - Fee #{fee.name}: #{fee_cents}"
          fees_cents += fee_cents
        end

        puts "### Expected fees_cents for remittance #{remittance.id} - commitment #{remittance.capital_commitment}: #{fees_cents}"
        puts "---------------------------------------------------------------------------------------------------"
        remittance.capital_fee_cents.should == fees_cents
        @remittance_fees[remittance.id] = fees_cents

        @remittance_call_amounts[remittance.id] = remittance.call_amount_cents
        expect(remittance.call_amount_cents).to eq(remittance.computed_amount_cents + remittance.capital_fee_cents + remittance.other_fee_cents)
      end
    end


  end

  When('I recompute the capital call fees') do
    visit(capital_call_url(@capital_call))
    within "#capital_call_#{@capital_call.id}_actions" do
      click_on("Actions")
    end
    click_on("Recompute Call")
    click_on("Proceed")
    sleep(2)
  end

  Then('The remittances should have the updated proper fees and call amount') do
    @capital_call.reload
    if @capital_call.call_fees.present?
      @capital_call.capital_remittances.reload.each_with_index do |remittance, idx|
        fees_cents = 0
        @capital_call.call_fees.each do |fee|
          fee_cents = remittance.capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", fee.start_date, fee.end_date, fee.name, false).sum(:amount_cents)
          puts "### Remittance #{remittance.id} - NEW Fee #{fee.name}: #{fee_cents}"
          fees_cents += fee_cents
        end
        puts "### Expected NEW fees_cents for remittance #{remittance.id} - commitment #{remittance.capital_commitment}: #{fees_cents}"
        remittance.capital_fee_cents.should == fees_cents
        @remittance_fees[remittance.id].should_not == fees_cents
        puts "### CHANGE in fees for remittance #{remittance.id} - commitment #{remittance.capital_commitment}: #{@remittance_fees[remittance.id]} - #{fees_cents} = #{@remittance_fees[remittance.id] - fees_cents}"

        puts "###Call Amount - Before: #{@remittance_call_amounts[remittance.id]} | After: #{remittance.call_amount_cents}"
        expect(@remittance_call_amounts[remittance.id]).not_to eq(remittance.call_amount_cents)
        puts "### CHANGE in call amount for remittance #{remittance.id} - commitment #{remittance.capital_commitment}: #{@remittance_call_amounts[remittance.id]} - #{remittance.call_amount_cents} = #{@remittance_call_amounts[remittance.id] - remittance.call_amount_cents}"
        expect(remittance.call_amount_cents).to eq(remittance.computed_amount_cents + remittance.capital_fee_cents + remittance.other_fee_cents)
        puts "---------------------------------------------------------------------------------------------------"
      end
    end
  end

  Then('I should see the capital call details') do
    find(".show_details_link").click
    @capital_call = CapitalCall.last
    expect(page).to have_content(@capital_call.name)
    expect(page).to have_content(@capital_call.close_percentages["First Close"].to_i) if  @capital_call.call_basis == "Percentage of Commitment"
    expect(page).to have_content(money_to_currency @capital_call.amount_to_be_called) if  @capital_call.amount_to_be_called_cents > 0

    expect(page).to have_content(@capital_call.due_date.strftime("%d/%m/%Y"))
  end

  Then('the remittances must be marked with notification sent') do
    @capital_call.capital_remittances.each do |remittance|
      remittance.notification_sent.should == true
    end
  end

  When('I mark the remittances as paid') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_remittance_url(remittance))
      click_on "New Payment"
      fill_in('capital_remittance_payment_folio_amount', with: remittance.due_amount)
      click_on "Save"
      # sleep(2)
      expect(page).to have_content("Capital remittance payment was successfully")
    end
  end

  When('I mark the remittances as verified') do

    @capital_call.capital_remittances.each do |remittance|
      visit(capital_call_url(@capital_call))
      #sleep((1)
      click_on "Remittances"
      #sleep((1)
      within("#capital_remittance_#{remittance.id}") do
        click_on "Actions"
        click_on "Verify"
        #sleep((1)
      end
      click_on "Proceed"
      #sleep((1)
    end
  end

Then('the capital call collected amount should be {string}') do |arg|
  #sleep((1)
  @capital_call.reload
  @capital_call.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
  @capital_call.fund.collected_amount.should == Money.new(arg.to_i * 100, @capital_call.fund.currency)
end

Then('the remittance rollups should be correct') do
  # Recalculate all counter caches from DB before asserting.
  # Needed because investor_kyc_id may be linked to commitments after remittances were
  # created, so the incremental counter_culture delta never ran for that KYC.
  CapitalRemittance.counter_culture_fix_counts
  # Call rollups
  CapitalCall.all.each do |capital_call|
    capital_call.reload
    puts "Checking rollups for #{capital_call.name}"
    capital_call.capital_fee_cents.should == capital_call.capital_remittances.sum(:capital_fee_cents)
    capital_call.other_fee_cents.should == capital_call.capital_remittances.sum(:other_fee_cents)
    capital_call.collected_amount_cents.should == capital_call.capital_remittances.verified.sum(:collected_amount_cents)
    capital_call.call_amount_cents.should == capital_call.capital_remittances.sum(:call_amount_cents)

    # Fund rollups
    fund = capital_call.fund
    puts "Checking rollups for fund #{fund.name}"
    fund.capital_fee_cents.should == fund.capital_remittances.sum(:capital_fee_cents)
    fund.other_fee_cents.should == fund.capital_remittances.sum(:other_fee_cents)
    fund.call_amount_cents.should == fund.capital_remittances.sum(:call_amount_cents)
    fund.collected_amount_cents.should == fund.capital_remittances.verified.sum(:collected_amount_cents)

    fund.capital_commitments.each do |cc|
      # Commitment rollups
      puts "Checking rollups for commitment #{cc}"
      cc.collected_amount_cents.should == cc.capital_remittances.verified.sum(:collected_amount_cents)
      cc.folio_collected_amount_cents.should == cc.capital_remittances.verified.sum(:folio_collected_amount_cents)
      cc.call_amount_cents.should == cc.capital_remittances.sum(:call_amount_cents)
      cc.folio_call_amount_cents.should == cc.capital_remittances.sum(:folio_call_amount_cents)

      # KYC rollups — aggregate through investor_kyc_id FK chain, matching counter_culture setup
      if cc.investor_kyc
        puts "Checking rollups for KYC #{cc.investor_kyc}"
        kyc_remittances = CapitalRemittance.joins(:capital_commitment).where(capital_commitments: { investor_kyc_id: cc.investor_kyc.id })
        cc.investor_kyc.reload
        cc.investor_kyc.call_amount_cents.should == kyc_remittances.sum(:call_amount_cents)
        cc.investor_kyc.collected_amount_cents.should == kyc_remittances.verified.sum(:collected_amount_cents)
        cc.investor_kyc.other_fee_cents.should == kyc_remittances.sum(:other_fee_cents)
      end
    end
  end
end

Given('the fund has {string} capital call') do |count|
  (1..count.to_i).each do |i|
    cc = FactoryBot.build(:capital_call, fund: @fund)
    CapitalCallCreate.wtf?(capital_call: cc)
    puts "\n####CapitalCall####\n"
    puts cc.to_json
  end

  @fund.reload
end

Given('the capital calls are approved') do
  @fund.capital_calls.each do |cc|
    cc.approved = true
    cc.approved_by_user = @user
    CapitalCallUpdate.wtf?(capital_call: cc)
  end
end

Given('the remittance have a document {string} from {string} attached') do |name, path|
  CapitalRemittance.all.each do |remittance|
    Document.create(entity_id: remittance.entity_id, owner: remittance, name: name, file: File.open(path, "rb"), user_id: @user.id)
  end
end

Then('when the capital call is approved') do
  @capital_call.approved = true
  @capital_call.approved_by_user = @user
  result = CapitalCallApprove.wtf?(capital_call: @capital_call)
  puts result
  result.success?.should == true
  #sleep((1)
  @capital_call.reload
end

Then('Given I upload {string} file for Call remittances of the fund') do |file|
  visit(capital_call_path(@capital_call))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Remittances")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  # sleep(2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(4)
  ImportUpload.last.failed_row_count.should == 0
  ImportUpload.last.status.should == "Completed"
end

Then('Given I upload {string} file for {string} of the fund with errors') do |file, tab|
  @import_file = file
  visit(fund_path(@fund))
  click_on(tab)
  if page.has_button?("Upload / Download")
    click_on("Upload / Download")
    click_on("Upload")
  else
    click_on("Upload")
  end
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  sleep(2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  expect(ImportUpload.last.failed_row_count).to be > 0
end

# Checks that the most recent import result file contains the given error message for at least one row
Then('the capital call should fail with error {string}') do |error_msg|
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  data = Roo::Spreadsheet.open(tempfile.path)
  headers = ImportServiceBase.new.get_headers(data.row(1))
  error_col = headers.length # result column appended after all data columns
  error_found = false
  data.each_with_index do |row, idx|
    next if idx.zero?
    error_found = true if row[error_col]&.include?(error_msg)
  end
  expect(error_found).to be(true), "Expected error '#{error_msg}' not found in import results"
end

Then('There should be {string} capital calls created') do |count|
  @fund.capital_calls.count.should == count.to_i
end

Then('the capital calls must have the data in the sheet') do
  file = File.open("./public/sample_uploads/#{@import_file}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  capital_calls = @fund.capital_calls.order(id: :asc).to_a
  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row

    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h
    cc = capital_calls[idx-1]
    puts "Checking import of #{cc.name}"
    cc.name.should == user_data["Name"].strip
    cc.fund.name.should == user_data["Fund"]
    cc.close_percentages["First Close"] == user_data["Percentage Called"].to_d
    cc.due_date.should == Date.local_parse(user_data["Due Date"])
    user_data["Unit Price/Premium"].split(",").each do |unit_price|
      puts "Checking unit price #{unit_price}"
      unit_type, price, premium = unit_price.split(":")
      cc.unit_prices[unit_type.strip]["price"].should == price
      cc.unit_prices[unit_type.strip]["premium"].should == premium
    end
    cc.import_upload_id.should == ImportUpload.last.id
  end
end

Then('the remittances are generated for the capital calls') do
  Fund.all.each do |fund|
    fund.capital_calls.each do |cc|

      commitments = fund.capital_commitments
      puts "Checking remittances for #{cc.name} #{commitments.count} #{cc.capital_remittances.count}"
      cc.capital_remittances.count.should == commitments.count
      cc.capital_remittances.sum(:call_amount_cents).should == cc.call_amount_cents
      cc.capital_remittances.verified.sum(:collected_amount_cents).should == cc.collected_amount_cents
      # Ensure status are set correctly post the import
      cc.capital_remittances.each do |cr|
        cr.status.should == cr.set_status if cr.verified
      end
    end
  end
end

Then('if the last remittance payment is deleted') do
  CapitalRemittancePayment.last&.destroy
end

Then('if the first remittance is deleted') do
  CapitalRemittance.first&.destroy
end

Given('the fund has capital call template') do
  @call_template = Document.create!(name: "Call Doc", owner_tag: "Call Template",
    owner: @fund, entity_id: @fund.entity_id, user: @user,
    file: File.new("public/sample_uploads/Drawdown notice format.docx", "r"))
end

Then('when the capital call docs are generated') do
  CapitalCall.all.each do |cc|
    visit(capital_call_path(cc))
    within "#capital_call_#{cc.id}_actions" do
      click_on("Actions")
    end
    click_on("Generate Documents")
    click_on("Proceed")
    # sleep(1)
    cc.capital_remittances.each_with_index do |cr, count|
      puts "Generating doc for remittance #{cr.id}. Sleeping 2 seconds...."
      sleep(2)
      # expect(page).to have_content("#{count + 1}: Generated #{@call_template.name} for #{cr}")
    end
    # expect(page).to have_content("generated successfully")
  end
end

Given('the generated call notices are approved') do
  # approve all generated docs so check_unapproved_docs in CapitalCallApprove does not block
  Document.generated.update_all(approved: true)
end

Then('Given I upload {string} file for the remittances of the capital call') do |file|
  @import_file = file
  visit(capital_call_path(@fund.capital_calls.first))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Payments")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  # binding.pry if ImportUpload.last.failed_row_count > 0
  # ImportUpload.last.failed_row_count.should == 0
end

Then('There should be {string} remittance payments created') do |count|
  CapitalRemittancePayment.count.should == count.to_i
end

Then('the capital remittance payments must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    capital_remittance_payments = @fund.capital_remittance_payments.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h

      cc = capital_remittance_payments[idx-1]

      cc.fund.name.should == user_data["Fund"]
      cc.capital_remittance.investor.investor_name.should == user_data["Stakeholder"]
      cc.capital_remittance.folio_id.should == user_data["Folio No"].to_s
      cc.folio_amount_cents.should == user_data["Amount (Folio Currency)"].to_i * 100

      capital_commitment = cc.capital_remittance.capital_commitment
      capital_commitment.folio_currency.should == user_data["Currency"]

      if user_data["Amount (Fund Currency)"].present?
        cc.amount_cents.should == user_data["Amount (Fund Currency)"].to_i * 100
      else
        amount = capital_commitment.foreign_currency? ? (cc.folio_amount_cents * capital_commitment.get_exchange_rate(capital_commitment.folio_currency, cc.fund.currency, cc.payment_date).rate) : cc.amount_cents
        cc.amount_cents.should == amount
      end


      cc.reference_no.should == user_data["Reference No"].to_s
      cc.payment_date.should == Date.local_parse(user_data["Payment Date"])
      cc.import_upload_id.should == ImportUpload.last.id


      # sleep(30)
    end
end

Given('the capital remittance whatsapp notification is sent to the first investor') do
  cr = CapitalRemittance.first
  cc = cr.capital_call
  cc.update_columns(approved:true, manual_generation: false)
  @resjob = cr.send_notification
end

Given('there is a custom notification for the capital call with subject {string} with email_method {string}') do |subject, email_method|
  @custom_notification = CustomNotification.create!(entity: @capital_call.entity, subject:, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call, email_method:)
end

Given('notification should be sent {string} to the remittance investors for {string}') do |sent, cn_args|
  cn = CustomNotification.new
  key_values(cn, cn_args)

  @capital_call.capital_remittances.each do |cr|
    user = cr.investor.investor_accesses.approved.first.user
    open_email(user.email)
    puts "Checking email for #{user.email} with email_method: #{cn.email_method}, subject: #{current_email&.subject}"
    if sent == "true"
      expect(current_email.subject).to include @capital_call.custom_notification(cn.email_method).subject
    else
      current_email.should == nil
    end
  end

end

Given('there is a custom notification {string} in place for the Call') do |args|
    @capital_call = CapitalCall.last
    @custom_notification = CustomNotification.build(entity: @entity, body: Faker::Lorem.paragraphs.join(". "), whatsapp: Faker::Lorem.sentences.join(". "), owner: @capital_call)
    key_values(@custom_notification, args)
    @custom_notification.save!
end

Then('Given I upload {string} file for the remittances of the capital call with errors') do |file|
  @import_file = file
  visit(capital_call_path(@fund.capital_calls.first))
  click_on("Remittances")
  #sleep((2)
  click_on("Upload / Download")
  click_on("Upload Payments")
  #sleep((2)
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  #sleep((2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(10)
  ImportUpload.last.failed_row_count.should_not == 0
end

Then('I should see the remittance payments upload errors') do
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  file = File.open(tempfile.path, "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    puts "row[headers.length] = #{row[headers.length]}"
    if idx < 7
      row[headers.length].include?("Success").should == true
    end
    if idx == 7
      row[headers.length].include?("Fund not found").should == true
    end
    if idx == 8
      row[headers.length].include?("Capital Call not found").should == true
    end
    if idx == 9
      row[headers.length].include?("Stakeholder not found").should == true
    end
    if idx == 10
      row[headers.length].include?("Folio No or Virtual Bank Account must be specified").should == true
    end
    if idx == 11
      row[headers.length].include?("Stakeholder commitment not found for folio C999").should == true
    end
    if idx == 12
      row[headers.length].include?("Stakeholder commitment not found for virtual bank account 99998888").should == true
    end
    if idx == 13
      row[headers.length].include?("Stakeholder commitment not found").should == true
    end
  end
end

Then('The proper documents must be uploaded for the remittances') do
  expect(ImportUpload.last.failed_row_count).to eq(6)
  doc1 = Document.where(name: "Remittance doc 1").first
  cc = CapitalCall.find_by(fund: @fund, name: "Capital Call 4")
  investor = Investor.find_by(investor_name: "Investor 1", entity: @fund.entity)
  expect(doc1.owner).to eq(CapitalRemittance.where(fund: @fund, folio_id: "6", investor_id: investor.id, capital_call_id: cc.id).first)
  doc2 = Document.where(name: "Remittance doc 2").first
  cc = CapitalCall.find_by(fund: @fund, name: "Capital Call 8")
  investor = Investor.find_by(investor_name: "Investor 2", entity: @fund.entity)
  expect(doc2.owner).to eq(CapitalRemittance.where(fund: @fund, folio_id: "7", investor_id: investor.id, capital_call_id: cc.id).first)
end

Then('I should see the remittance docs upload errors') do
  import_upload = ImportUpload.last
  tempfile = import_upload.import_results.download
  file = File.open(tempfile.path, "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

  # The commented out checks are for errors that are no longer generated due to changes in the import which does not check the kyc now.
  data.each_with_index do |row, idx|
    p row[headers.length]
    next if idx.zero? # skip header row
    if idx == 1 or idx == 2
      row[headers.length].include?("Success").should == true
    end
    if idx == 3
      row[headers.length].include?("Call Name not found").should == true
    end
    if idx == 4
      row[headers.length].include?("Capital Call not found for Some capital call").should == true
    end
    if idx == 5
      # row[headers.length].include?("Capital Remittance not found for SAAS Fund, Capital Call 25, 55 and Investor 6").should == true
    end
    if idx == 6
      row[headers.length].include?("Fund is blank").should == true
    end
    if idx == 7
      # row[headers.length].include?("Investing Entity is blank").should == true
    end
    if idx == 8
      row[headers.length].include?("Folio No is blank").should == true
    end
    if idx == 9
      row[headers.length].include?("file1.pdf cannot be uploaded again").should == true
    end
  end
end

Then('call notice is generated for the remittances') do
  @capital_call = @fund.capital_calls.first
  visit(capital_call_path(@capital_call))
  within "#capital_call_#{@capital_call.id}_actions" do
    click_on("Actions")
  end
  click_on("Generate Documents")
  click_on("Proceed")
  sleep(2)
  # With :inline job adapter the job runs synchronously and the completion flash
  # ("N documents generated successfully") replaces the async "started" flash
  # before any fixed sleep could catch it.  Accept either message.
  expect(page).to have_content(
    /Documentation generation started|documents generated/i,
    wait: 20
  )
end

Then('remittance notice must be generated for each remittance') do
  @capital_call ||= @fund.capital_calls.first
  call_template_name = @capital_call.fund.documents.where(owner_tag: "Call Template").last.name
  @capital_call.capital_remittances.each do |cr|
    cr.documents.pluck(:name).include?("#{call_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should == true
  end
end

Given('I approve the capital call') do
  @user.add_role :approver
  @user.save!
  @capital_call.remittance_documents.update_all(approved: true)
  @capital_call.update_columns(send_call_notice_flag: true, manual_generation: false)

  visit(capital_call_path(@capital_call))
  within "#capital_call_#{@capital_call.id}_actions" do
    click_on("Actions")
  end
  click_on("Approve")
  click_on("Confirm & Save")

end

Given('the remittances have proper notification users') do
  @capital_call ||= @fund.capital_calls.first
  @capital_call.capital_remittances.each do |cr|
    if cr.investor.notification_users(@fund).blank?
      investor = cr.investor
      user = FactoryBot.create(:user, entity: investor.investor_entity)
      user.permissions.set(:enable_funds)
      user.save!
      user.entity.permissions.set(:enable_funds)
      user.entity.save!
      if @fund.access_rights.where(access_to_investor_id: cr.investor_id).blank?
        AccessRight.create!(entity: @fund.entity, access_to_investor_id: cr.investor_id, metadata: "investor", access_type: "Fund", owner: @fund)
      end
      InvestorAccess.create!(email: user.email, investor: investor, approved: true, entity: investor.entity, first_name: user.first_name, last_name: user.last_name, user: @user, email_enabled: true)
      user.reload
    end
  end
  @fund.reload
end

Then('the notification must be sent to the investors where the call notice was generated') do
  @capital_call ||= @fund.capital_calls.first
  puts "Total Notifications - #{ Noticed::Notification.count }"
  call_template_name = @capital_call.fund.documents.where(owner_tag: "Call Template").last.name
  @capital_call.capital_remittances.each do |cr|
    if cr.documents.pluck(:name).include?("#{call_template_name} - #{cr.investor_kyc} - #{cr.folio_id}")
      cr.investor.notification_users(@fund).each do |nu|
        current_email = nil
        emails_sent_to(nu.email).each do |email|
          puts "#{email.subject} #{email.to} #{email.cc} #{email.bcc}"
          current_email = email if email.subject.include?("#{cr.fund.name}: #{cr.capital_call.name}")
        end
        puts "Checking email to #{nu.email} for remittance #{cr.id}"
        expect(current_email.body).to include "Please refer to the attached notice for further details or click on the link below"
      end
    else

    end
  end
end

Given('I update the remittances commitments custom fields with the same kyc and earlier remittance date {string}') do |custom_fields|
  @capital_call ||= @fund.capital_calls.first

  # Load all remittances for the call, with their commitments + KYC,
  # ordered so that within each KYC group, the latest remittance is last.
  remittances = @capital_call.capital_remittances
                             .joins(:capital_commitment)
                             .includes(:capital_commitment)
                             .where.not(capital_commitments: { investor_kyc_id: nil })
                             .order(
                               'capital_commitments.investor_kyc_id ASC',
                               'capital_remittances.remittance_date ASC',
                               'capital_remittances.id ASC'
                             )

  # Group by KYC (through the commitment)
  remittances.group_by { |cr| cr.capital_commitment.investor_kyc_id }.each_value do |group|
    # If only one remittance for that KYC, nothing to "earlier" update
    next if group.size <= 1

    # Take all except the latest (last in the sorted group)
    group[0..-2].each do |cr|
      puts "Updating commitment #{cr.capital_commitment.id} for remittance #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id}"
      # Assuming key_values(model, attrs_string) assigns attributes from attrs
      custom_fields.split(",").each do |cf|
        k, v = cf.split(":").map(&:strip)
        cr.capital_commitment.json_fields[k] = v
      end
      cr.capital_commitment.save!
    end
  end
end

Then('remittance notice must be generated for the latest remittance for each kyc') do
  @capital_call ||= @fund.capital_calls.first

  # Load all remittances for the call, with their commitments + KYC,
  # ordered so that within each KYC group, the latest remittance is last.
  remittances = @capital_call.capital_remittances
                             .joins(:capital_commitment)
                             .includes(:capital_commitment)
                             .where.not(capital_commitments: { investor_kyc_id: nil })
                             .order(
                               'capital_commitments.investor_kyc_id ASC',
                               'capital_remittances.remittance_date ASC',
                               'capital_remittances.id ASC'
                             )

  # Group by KYC (through the commitment)
  call_template_name = @capital_call.fund.documents.where(owner_tag: "Call Template").last.name
  remittances.group_by { |cr| cr.capital_commitment.investor_kyc_id }.each_value do |group|
    # If only one remittance for that KYC, then it should have the notice generated, so we will check that in the loop itself. We only need this "earlier remittance" logic if there are multiple remittances for the same KYC

    if group.size == 1
      cr = group.first
      puts "Only one remittance #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id}, checking if notice is generated"
      cr.documents.pluck(:name).include?("#{call_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should == true
      next
    end

    # Take all except the latest (last in the sorted group)
    group[0..-2].each do |cr|
      puts "Checking remittance #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id} is NOT generated"
      cr.documents.pluck(:name).include?("#{call_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should == false
    end
    group.last.tap do |cr|
      puts "Checking remittance #{cr.id} for KYC #{cr.capital_commitment.investor_kyc_id} IS generated"
      cr.documents.pluck(:name).include?("#{call_template_name} - #{cr.investor_kyc} - #{cr.folio_id}").should == true
    end
  end
end

Then('no capital remittances should be created') do
  @capital_call = CapitalCall.last
  CapitalRemittance.where(capital_call: @capital_call).count.should == 0
end

Then('the generated call notices have as_of set to the remittance date') do
  CapitalRemittance.all.each do |cr|
    doc = cr.documents.where(from_template_id: @call_template.id).last
    puts "Checking call notice as_of for remittance #{cr.id}: doc.as_of=#{doc&.as_of}, remittance_date=#{cr.remittance_date}"
    expect(doc).to be_present, "Expected a generated document for remittance #{cr.id}"
    expect(doc.as_of).to eq(cr.remittance_date)
  end
end


  Then('the no remittances should be created') do
    @capital_call = CapitalCall.last
    @capital_call.capital_remittances.count.should == 0
  end

  Then('the corresponding remittances should be created') do

    @capital_call = CapitalCall.last
    if @capital_call.call_basis != "Upload"
      @capital_call.capital_remittances.count.should == @fund.capital_commitments.count
    end

    @capital_call.capital_remittances.each_with_index do |remittance, idx|
        ap remittance
        cc = remittance.capital_commitment
        if @capital_call.call_basis == "Amount allocated on Investable Capital"
          ((@capital_call.amount_to_be_called * remittance.percentage / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Percentage of Commitment"
          ((cc.committed_amount * @capital_call.close_percentages["First Close"].to_f / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Upload"
          file = File.open("./public/sample_uploads/capital_remittances.xlsx", "r")
          data = Roo::Spreadsheet.open(file.path) # open spreadsheet
          headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
          row = data.row(idx+2)
          # create hash from headers and cells
          user_data = [headers, row].transpose.to_h

          puts "Checking import of #{user_data}"
          remittance.investor.investor_name.should == user_data["Stakeholder"].strip
          remittance.fund.name.should == user_data["Fund"]
          remittance.capital_call.name.should == user_data["Capital Call"]

          remittance.folio_call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Folio Currency)"].to_f * 100
          remittance.folio_capital_fee_cents.should == user_data["Capital Fees (Folio Currency)"].to_f * 100
          remittance.folio_other_fee_cents.should == user_data["Other Fees (Folio Currency)"].to_f * 100

          remittance.call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].to_f * 100 if user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].present?
          remittance.capital_fee_cents.should == user_data["Capital Fees (Fund Currency)"].to_f * 100 if user_data["Capital Fees (Fund Currency)"].present?
          remittance.other_fee_cents.should == user_data["Other Fees (Fund Currency)"].to_f * 100 if user_data["Other Fees (Fund Currency)"].present?

          remittance.status.should == "Pending"
          remittance.verified.should == (user_data["Verified"] == "Yes")
        end

        # Check the fees
        if @capital_call.call_fees.present?
          @capital_call.call_fees.each do |fee|
            binding.pry if remittance.capital_fee_cents == 0
            remittance.capital_fee_cents.should > 0
            # remittance.other_fee_cents.should > 0
          end
        end
    end
  end

  Then('I should see the remittances') do
    @capital_call.reload
    # @fund.capital_commitments.count.should == @fund.investors.count
    @capital_call.capital_remittances.count.should == @fund.capital_commitments.count

    visit(capital_call_url(@capital_call))
    #sleep((2)
    click_on "Remittances"

    @capital_call.capital_remittances.each do |remittance|
        within("#capital_remittance_#{remittance.id}") do
            expect(page).to have_content(remittance.investor.investor_name)
            expect(page).to have_content(remittance.verified ? "Yes" : "No")
            expect(page).to have_content(remittance.status)
            expect(page).to have_content(money_to_currency remittance.due_amount)
            expect(page).to have_content(money_to_currency remittance.collected_amount)
        end
    end
  end

  Then('the corresponding remittances should be created with fees') do
    @capital_call = CapitalCall.last
    if @capital_call.call_basis != "Upload"
      @capital_call.capital_remittances.count.should == @fund.capital_commitments.count
    end

    @capital_call.capital_remittances.each_with_index do |remittance, idx|
        cc = remittance.capital_commitment
        if @capital_call.call_basis == "Amount allocated on Investable Capital"
          ((@capital_call.amount_to_be_called * remittance.percentage / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Percentage of Commitment"
          ((cc.committed_amount * @capital_call.close_percentages["First Close"].to_f / 100.0) + remittance.capital_fee - remittance.collected_amount).should == remittance.due_amount
        elsif @capital_call.call_basis == "Upload"
          file = File.open("./public/sample_uploads/capital_remittances.xlsx", "r")
          data = Roo::Spreadsheet.open(file.path) # open spreadsheet
          headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
          row = data.row(idx+2)
          # create hash from headers and cells
          user_data = [headers, row].transpose.to_h

          puts "Checking import of #{user_data}"
          remittance.investor.investor_name.should == user_data["Stakeholder"].strip
          remittance.fund.name.should == user_data["Fund"]
          remittance.capital_call.name.should == user_data["Capital Call"]

          remittance.folio_call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Folio Currency)"].to_f * 100
          remittance.folio_capital_fee_cents.should == user_data["Capital Fees (Folio Currency)"].to_f * 100
          remittance.folio_other_fee_cents.should == user_data["Other Fees (Folio Currency)"].to_f * 100

          remittance.call_amount_cents.should == user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].to_f * 100 if user_data["Call Amount (Inclusive Of Capital Fees, Fund Currency)"].present?
          remittance.capital_fee_cents.should == user_data["Capital Fees (Fund Currency)"].to_f * 100 if user_data["Capital Fees (Fund Currency)"].present?
          remittance.other_fee_cents.should == user_data["Other Fees (Fund Currency)"].to_f * 100 if user_data["Other Fees (Fund Currency)"].present?

          remittance.status.should == "Pending"
          remittance.verified.should == (user_data["Verified"] == "Yes")
        end

        # Check the fees
        if @capital_call.call_fees.present?
          fees_cents = 0
          @capital_call.call_fees.each do |fee|
            fees_cents += remittance.capital_commitment.account_entries.where("account_entries.reporting_date >=? and account_entries.reporting_date <=? and account_entries.name = ? and cumulative = ?", fee.start_date, fee.end_date, fee.name, false).sum(:amount_cents)
            # remittance.other_fee_cents.should > 0
          end
          puts "### Expected fees_cents for remittance #{remittance.id} - commitment #{remittance.capital_commitment}: #{fees_cents}"
          puts "---------------------------------------------------------------------------------------------------"

          remittance.capital_fee_cents.should == fees_cents
        end
    end
  end

Then('the generated doc must be attached to the capital remittances') do
  CapitalRemittance.all.each do |cc|
    docs = cc.documents.where(from_template_id: @call_template.id)
    docs.count.should == 1
    puts "Checking documents for remittance #{cc.id}. Got #{docs.first.name}"
    visit(capital_remittance_path(cc))
    within("#remittance_details") do
      click_on("Documents")
      expect(page).to have_content(@call_template.name)
      expect(page).to have_content("Generated")
    end
  end
end
