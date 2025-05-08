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

