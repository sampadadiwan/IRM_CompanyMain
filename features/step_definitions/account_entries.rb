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
