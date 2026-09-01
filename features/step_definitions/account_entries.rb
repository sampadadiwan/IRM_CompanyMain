Given("there are Fund Formulas are added to the fund") do
	AllocationRun.delete_all
	fund_formula = @fund.fund_formulas.build(
														name: "Test Allocation",
														description: "Some random description",
														formula:
														"capital_commitment.arrear_folio_amount_cents + capital_commitment.arrear_amount_cents",
														sequence: 31,
														rule_type: "GenerateAccountEntry",
														enabled: true,
														entry_type: "Accounting",
														roll_up: false,
														rule_for: "Accounting",
													)
	fund_formula.save!
end

Given("there are chained Fund Formulas relying on a computed field without the cache flag set") do
	AllocationRun.delete_all
	# Deliberately leaves add_to_commitment_cache at its default (false, since
	# 20260829090000_default_add_to_commitment_cache_to_false.rb) on both formulas.
	# The second formula only computes correctly if AccountEntryAllocation::CommitmentCache
	# caches "net_income" because the second formula's source references @net_income
	# (FundFormula#referenced_field_names), not because a formula author remembered to
	# flip the flag -- that's the whole point of this regression test.
	base_formula = @fund.fund_formulas.build(
															name: "Net Income",
															description: "Base value the next formula depends on",
															formula: "100000",
															sequence: 10,
															rule_type: "GenerateAccountEntry",
															enabled: true,
															entry_type: "Accounting",
															roll_up: false,
															rule_for: "Accounting",
														)
	base_formula.save!

	dependent_formula = @fund.fund_formulas.build(
															name: "Net Income Times Two",
															description: "Depends on @net_income from the formula above",
															formula: "@net_income * 2",
															sequence: 20,
															rule_type: "GenerateAccountEntry",
															enabled: true,
															entry_type: "Accounting",
															roll_up: false,
															rule_for: "Accounting",
														)
	dependent_formula.save!
end

Then("the dependent formula's account entry reflects the earlier formula's computed value") do
	ae = AccountEntry.find_by(name: "Net Income Times Two", fund_id: @fund.id)
	expect(ae).to(be_present)
	expect(ae.amount_cents.to_i).to(eq(200_000))
end

Given("that Account Entries are allocated") do
	visit allocate_form_fund_path(@fund.id, run_allocations: true)
	sleep(1)
	click_on("Submit")
	sleep(1)
end

Then("I see AllocationRun created") do
	visit allocate_form_fund_path(@fund.id, run_allocations: true)
	eventually { expect(AllocationRun.last).to be_present }
	@allocation_run = AllocationRun.last
	within('table') do
    expect(page).to have_css('tr', text: I18n.l(@allocation_run.start_date, format: :abbr_month_day_year))
    expect(page).to have_css('tr', text: I18n.l(@allocation_run.end_date, format: :abbr_month_day_year))
  end
  eventually { expect(AccountEntry.last).to(be_present) }
end

Given("I lock the AllocationRun") do
	first('tbody tr').find('.dtr-control').click
	click_on("Lock")
	sleep(1)
end

Then("I get the error on AllocationRun creation") do
	expect(AllocationRun.count).to(eq(1))
	 expect(page).to have_text("This AllocationRun already exists for the specified period and is locked")  # Wait for the error message
end


Given('I am at the capital commitment page') do
  @capital_commitment = CapitalCommitment.last
	visit(capital_commitment_path(@capital_commitment))
end

Given('I add a new account entry') do
	# This is to scroll to the Account Entries tab and click it, otherwise the turbo_frame does not lazy load unless you scroll to it
	click_tab("Account Entries")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
	expect(page).to have_content("New Account Entry", wait: 10)
	click_on("New Account Entry")
	fill_in("account_entry_period", with: "Q1")
	fill_in("account_entry_name", with: "Test Account Entry")
	fill_in("account_entry_amount", with: 100000)
	fill_in("account_entry_notes", with: "Test Account Entry")
	click_on("Save")
end

Then('I edit the account entry with debug {string}') do |debug_string|
  @account_entry ||= AccountEntry.where(generated: false).last
	@parent = @capital_commitment.investor
	debug = debug_string == "true"
	puts "######## ACCOUNT ENTRY ##########"
	puts @account_entry.inspect
	visit(edit_account_entry_path(@account_entry, debug: debug))
	fill_in("account_entry_name", with: "Test Account Entry Updated")
	fill_in("account_entry_parent_type", with: @parent.class.name)
	fill_in("account_entry_parent_id", with: @parent.id)
	click_on("Save")
end

Then('the account entry parent is updated') do
	expect(page).to have_text("Account entry was successfully updated.")
  @parent ||= @capital_commitment.investor
	@account_entry ||= AccountEntry.where(generated: false).last
	puts "######## ACCOUNT ENTRY ##########"
	puts @account_entry.reload.inspect
	expect(@account_entry.reload.parent).to(eq(@parent))
	# parent_name is a denormalized cache of parent.to_s (AccountEntryShared#setup_defaults) --
	# assert it was populated alongside .parent, not just left to a separate manual check.
	expect(@account_entry.parent_name).to(eq(@parent.to_s[0..254]))
end

# PortfolioInvestment fixture used to re-point an already-parented account entry (see the
# "Edit Account Entry parent" scenario). Bypasses FactoryBot/validations via save!(validate:
# false), mirroring "there is a portfolio investment record for the fund" in
# access_rights_models_steps.rb -- kept as its own step (rather than reused directly) so this
# scenario owns a dedicated @pi_parent ivar instead of the shared, easily-clobbered @record.
Given('there is a portfolio investment for the account entry parent test') do
	pc_entity = Entity.create!(
		name: "PC Entity #{SecureRandom.hex(4)}",
		entity_type: "Investor",
		primary_email: "pc#{SecureRandom.hex(4)}@example.com"
	)
	portfolio_company = Investor.new(
		entity: @fund.entity,
		investor_entity: pc_entity,
		investor_name: pc_entity.name,
		category: "Portfolio Company"
	)
	portfolio_company.save!(validate: false)
	instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: portfolio_company)
	aggregate = AggregatePortfolioInvestment.new(
		fund: @fund,
		entity: @fund.entity,
		portfolio_company: portfolio_company,
		investment_instrument: instrument
	)
	aggregate.save!(validate: false)
	@pi_parent = PortfolioInvestment.new(
		fund: @fund,
		entity: @fund.entity,
		investment_instrument: instrument,
		portfolio_company: portfolio_company,
		aggregate_portfolio_investment: aggregate,
		amount_cents: 10_000_000,
		investment_date: Time.zone.today - 1.month,
		quantity: 100,
		sub_category: "Equity",
		category: "Unlisted",
		excused_folio_ids: []
	)
	@pi_parent.save!(validate: false)
end

Then('I re-point the account entry parent to the portfolio investment with debug {string}') do |debug_string|
	debug = debug_string == "true"
	visit(edit_account_entry_path(@account_entry, debug: debug))
	fill_in("account_entry_parent_type", with: @pi_parent.class.name)
	fill_in("account_entry_parent_id", with: @pi_parent.id)
	click_on("Save")
end

Then('the account entry parent and parent name reflect the portfolio investment') do
	expect(page).to have_text("Account entry was successfully updated.")
	@account_entry.reload
	expect(@account_entry.parent).to(eq(@pi_parent))
	# This is the actual regression check: setup_defaults used to write parent_name via
	# `self.parent_name ||= parent.to_s[0..254] if parent_name.blank? && parent.present?`, which
	# only ever fired once. Since @account_entry already had a parent_name cached from the
	# Investor parent set earlier in this scenario, the old code left that stale name in place
	# even though .parent (asserted above) correctly moved to @pi_parent.
	expect(@account_entry.parent_name).to(eq(@pi_parent.to_s[0..254]))
end


Then('an account entry is created for the commitment') do
	expect(page).to have_text("Account entry was successfully created.")
	ae = AccountEntry.last
	expect(ae.capital_commitment_id).to(eq(@capital_commitment.id))
	@capital_commitment.reload
	expect(@capital_commitment.account_entries).to(include(ae))
	expect(ae.fund).to (eq(@capital_commitment.fund))
end

Given('the Allocation Run {string} is created for the {string}') do |args, fund_name|
	fund = Fund.find_by(name: fund_name)
	key_val = args.split(";").to_h { |kv| kv.split("=") }

	allocation_run = AllocationRun.create!(fund: fund, entity_id: fund.entity_id, start_date: key_val["start_date"], end_date: key_val["end_date"], run_allocations: true, user_id: User.first.id)


	AccountEntryAllocationJob.perform_now(fund.id, Date.local_parse(key_val["start_date"]), Date.local_parse(key_val["end_date"]), rule_for: "", tag_list: nil, run_allocations: true, explain: true, user_id: User.first.id, generate_soa: false, template_id: nil, fund_ratios: false, sample: false, allocation_run_id: allocation_run.id)

end

Then('the account entries generated match the account entries in {string}') do |generated_account_entries|

  file = File.open("public/sample_uploads/#{generated_account_entries}", "r")
  data = Roo::Spreadsheet.open(file.path) # open spreadsheet
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
  count = 0

  data.each_with_index do |row, idx|
    next if idx.zero? # skip header row
    user_data = [headers, row].transpose.to_h
	puts "Processing row #{idx + 1}: #{user_data.inspect}"
	fund = Fund.find_by(name: user_data["Fund"].strip)
	raise "Fund not found for row #{idx + 1} with data: #{user_data.inspect}" unless fund

	capital_commitment = user_data["Folio"].present? ? CapitalCommitment.find_by(folio_id: user_data["Folio"].strip, fund_id: fund.id, investor_name: user_data["Investor"]) : nil
	cumulative = user_data["Cumulative"] == "Yes"
	parent = nil
	parent = user_data["Parent Type"].constantize.find(user_data["Parent Id"]) if user_data["Parent Type"].present? && user_data["Parent Id"].present? && false
	parent_name = user_data["Parent"].presence
	reporting_date = Date.strptime(user_data["Reporting Date"], "%d-%m-%Y")

	account_entry = nil

	ActiveRecord::Base.connection.clear_query_cache

	AccountEntry.uncached do
		if parent_name.present?
			if user_data["Ref Id"].present?
				account_entry = AccountEntry.find_by(name: user_data["Name"], entry_type: user_data["Entry Type"], capital_commitment_id: capital_commitment&.id, fund_id: fund.id, reporting_date: reporting_date, cumulative: cumulative, parent_name:, ref_id: user_data["Ref Id"])
			else
				account_entry = AccountEntry.find_by(name: user_data["Name"], entry_type: user_data["Entry Type"], capital_commitment_id: capital_commitment&.id, fund_id: fund.id, reporting_date: reporting_date, cumulative: cumulative, parent_name:)
			end
		else
			account_entry = AccountEntry.find_by(name: user_data["Name"], entry_type: user_data["Entry Type"], capital_commitment_id: capital_commitment&.id, fund_id: fund.id, reporting_date: reporting_date, cumulative: cumulative)
		end
	end

	if account_entry.nil?
		puts "capital_commitment_id: #{capital_commitment&.id}, fund_id: #{fund.id}, reporting_date: #{user_data["Reporting Date"]}, cumulative: #{cumulative}, parent_name: #{parent_name}, ref_id: #{user_data["Ref Id"]}, reporting_date: #{reporting_date}"
		binding.pry
	end
	account_entry.should_not be_nil, "Account entry not found for row #{idx + 1} with data: #{user_data.inspect}"

	account_entry.parent_type = user_data["Parent Type"] if user_data["Parent Type"].present?


	if account_entry.entry_type == "Percentage" || account_entry.name.include?("Percentage")
		tolerance = 0.5
		binding.pry if (account_entry.amount_cents.round(8) - user_data["Amount"].to_f.round(8)).abs > tolerance
		account_entry.amount_cents.round(8).should be_within(tolerance).of(user_data["Amount"].to_f.round(8))
	else
		tolerance = 2
		binding.pry if (account_entry.amount_cents.round(8) - user_data["Amount"].to_f.round(8) * 100).abs > tolerance
		account_entry.amount_cents.round(8).should be_within(tolerance).of(user_data["Amount"].to_f.round(8) * 100)
	end

	count = idx
  end

  count.should == 810

end


Then('the AllocationRun status is set to {string}') do |status|
	allocation_run = AllocationRun.last
	expect(allocation_run.status).to(eq(status))
end


Then('Given I upload {string} file for Account Entries') do |file|
  @import_file = file
  visit(capital_commitment_path(@fund.capital_commitments.first))
  click_on("Account Entries")
  #sleep((1)
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content("Upload", wait:5)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((1)
  click_on("Save")
  expect(page).to have_content("Import Upload:")
  # sleep(2)
  ImportUploadJob.perform_now(ImportUpload.last.id)
  # sleep(4)
  # binding.pry if ImportUpload.last.failed_row_count > 0
  ImportUpload.last.failed_row_count.should == 0
  ImportUpload.last.status.should == "Completed"
end

Then('There should be {string} account_entries created') do |count|
  AccountEntry.count.should == count.to_i
end

Given('Given I upload {string} {string} error file for Account Entries') do |file, err_count|
  @import_file = file
  visit(capital_commitment_path(@fund.capital_commitments.first))
  click_tab("Account Entries")
  page.execute_script('window.scrollTo(0, document.body.scrollHeight);')
  expect(page).to have_content("Upload", wait: 10)
  click_on("Upload")
  fill_in('import_upload_name', with: "Test Upload")
  attach_file('files[]', File.absolute_path("./public/sample_uploads/#{@import_file}"), make_visible: true)
  #sleep((2)
  click_on("Save")
  #sleep((2)
  expect(page).to have_content("Import Upload:")
  ImportUploadJob.perform_now(ImportUpload.last.id)
  #sleep((4)
  ImportUpload.last.failed_row_count.should == err_count.to_i
end

Then('I should see that the duplicate account entries are not uploaded') do
  # last 5 account entries are duped
  file = ImportUpload.last.import_results.download
  data = Roo::Spreadsheet.open(file.path)
  headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row
  # data from 21st row should have error "Duplicate, already present"
  data.each_with_index do |row, idx|
    next if idx < 21 # skip rows
    # column after headers should have error "Duplicate, already present"
    row[headers.length].include?("Duplicate Account Entry").should == true
  end
end

Then('the account_entries must have the data in the sheet') do
    file = File.open("./public/sample_uploads/#{@import_file}", "r")
    data = Roo::Spreadsheet.open(file.path) # open spreadsheet
    headers = ImportServiceBase.new.get_headers(data.row(1)) # get header row

    account_entries = @fund.account_entries.order(id: :asc).to_a
    data.each_with_index do |row, idx|
      next if idx.zero? # skip header row

      # create hash from headers and cells
      user_data = [headers, row].transpose.to_h
      ap user_data
      cc = account_entries[idx-1]
      ap cc

      puts "Checking import of #{cc.name}"
      cc.name.should == user_data["Name"].strip
      cc.fund.name.should == user_data["Fund"]
      # The investor is now derived from the folio's commitment, not from an Investor column
      cc.investor.should == cc.capital_commitment&.investor
      cc.folio_id.should == user_data["Folio No"].to_s
      cc.amount_cents.should == user_data["Amount (Fund Currency)"].to_f * 100
      cc.folio_amount_cents.should == user_data["Amount (Folio Currency)"].to_f * 100 if user_data["Amount (Folio Currency)"].present?
      cc.entry_type.should == user_data["Entry Type"]
      cc.reporting_date.should == Date.local_parse(user_data["Reporting Date"]) if user_data["Reporting Date"].present?
      cc.notes.should == user_data["Notes"]
      cc.import_upload_id.should == ImportUpload.where(import_type: "AccountEntry").last.id
    end

end

Then('the account_entries must visible for each commitment') do
  @fund.account_entries.each do |ae|
    visit(capital_commitment_path(ae.capital_commitment))
    click_on "Account Entries"
    expect(page).to have_content(ae.name)
    expect(page).to have_content(ae.entry_type)
    if ae.name.include?("Percentage")
      expect(page).to have_content("#{ae.amount_cents} %")
    else
      expect(page).to have_content(money_to_currency(ae.amount, {}))
    end
    expect(page).to have_content(ae.capital_commitment.folio_id)
    expect(page).to have_content(ae.reporting_date.strftime("%d/%m/%Y"))
  end
end

Then('the account entries are adjusted upon fund unit transfer') do

  transfer_ratio = @transfer_ratio
  retained_ratio = 1 - transfer_ratio

  @from_cc.account_entries.each do |entry|
    if entry.json_fields["transfer_id"].present?
      puts "Checking account entry for #{entry.id} for #{@from_cc.folio_id} to contain transfer_id #{@transfer_token}"
      entry.json_fields["transfer_id"].should == @transfer_token
      # entry.json_fields["orig_amount"].should == entry.amount_cents / retained_ratio
      entry.amount_cents.round(0).should == (entry.json_fields["orig_amount"].to_f * retained_ratio).round(0)
    end
  end

  @to_cc.account_entries.each do |entry|
    if entry.json_fields["transfer_id"].present?
      puts "Checking account entry for #{entry.id} for #{@to_cc.folio_id} to contain transfer_id #{@transfer_token}"
      entry.json_fields["transfer_id"].should == @transfer_token
      entry.investor_id.should == @to_cc.investor_id
      entry.folio_id.should == @to_cc.folio_id
      entry.commitment_name.should == @to_cc.to_s
      # entry.json_fields["orig_amount"].should == entry.amount_cents / transfer_ratio
      entry.amount_cents.round(0).should == (entry.json_fields["orig_amount"].to_f * transfer_ratio).round(0)
    end
  end
end

Then('account entries are not affected by the transfer') do
  @from_cc.reload
  @to_cc.reload

  @from_cc.account_entries.each do |entry|
    entry.json_fields["transfer_id"].should be_nil
  end

  @to_cc.account_entries.select { |e| e.json_fields["transfer_id"].present? }.should be_empty
end

Then('the other account entries are pro-rated') do
  retained = 1 - @transfer_ratio

  @from_cc.account_entries.each do |entry|
    next unless entry.json_fields["transfer_id"] == @transfer_token
    next if entry.name == @excluded_ae_name
    entry.amount_cents.round(0).should == (entry.json_fields["orig_amount"].to_f * retained).round(0)
  end

  @to_cc.account_entries.each do |entry|
    next unless entry.json_fields["transfer_id"] == @transfer_token
    next if entry.name == @excluded_ae_name
    entry.amount_cents.round(0).should == (entry.json_fields["orig_amount"].to_f * @transfer_ratio).round(0)
  end
end
