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

Given("that Account Entries are allocated") do
	visit allocate_form_fund_path(@fund.id, run_allocations: true)
	sleep(1)
	click_on("Submit")
	sleep(1)
end

Then("I see AllocationRun created") do
	visit allocate_form_fund_path(@fund.id, run_allocations: true)
	@allocation_run = AllocationRun.last
	within('table') do
    expect(page).to have_css('tr', text: @allocation_run.start_date.strftime('%d/%m/%Y'))
    expect(page).to have_css('tr', text: @allocation_run.end_date.strftime('%d/%m/%Y'))
  end
  expect(AccountEntry.last).to(be_present)
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
	click_on("Account Entries")
	click_on("New Account Entry")
	fill_in("account_entry_period", with: "Q1")
	fill_in("account_entry_name", with: "Test Account Entry")
	fill_in("account_entry_amount", with: 100000)
	fill_in("account_entry_notes", with: "Test Account Entry")
	click_on("Save")
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

  	
	AccountEntryAllocationJob.perform_now(fund.id, Date.parse(key_val["start_date"]), Date.parse(key_val["end_date"]), rule_for: "", tag_list: nil, run_allocations: true, explain: true, user_id: User.first.id, generate_soa: false, template_id: nil, fund_ratios: false, sample: false, allocation_run_id: allocation_run.id)

end

Then('the account entries generated match the accoun entries in {string}') do |string|

  file = File.open("./public/sample_uploads/allocate_account_entries/generated_account_entries.xlsx", "r")
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

	if parent_name.present?
		account_entry = AccountEntry.find_by(name: user_data["Name"], entry_type: user_data["Entry Type"], capital_commitment_id: capital_commitment&.id, fund_id: fund.id, reporting_date: user_data["Reporting Date"], cumulative:, parent_name:)
	else		
		account_entry = AccountEntry.find_by(name: user_data["Name"], entry_type: user_data["Entry Type"], capital_commitment_id: capital_commitment&.id, fund_id: fund.id, reporting_date: user_data["Reporting Date"], cumulative:)
	end

	account_entry.should_not be_nil, "Account entry not found for row #{idx + 1} with data: #{user_data.inspect}"

	account_entry.parent_type = user_data["Parent Type"] if user_data["Parent Type"].present?

	if account_entry.entry_type == "Percentage" || account_entry.name.include?("Percentage")
		# binding.pry if (account_entry.amount_cents.round(8) - user_data["Amount"].to_f.round(8)).abs > 0.5
		account_entry.amount_cents.round(8).should be_within(0.5).of(user_data["Amount"].to_f.round(8))
	else
		# binding.pry if (account_entry.amount_cents.round(8) - user_data["Amount"].to_f.round(8) * 100).abs > 0.5
		account_entry.amount_cents.round(8).should be_within(0.5).of(user_data["Amount"].to_f.round(8) * 100)
	end

	count = idx
  end
  
  count.should == 690

end
