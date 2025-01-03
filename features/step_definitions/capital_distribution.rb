When("I create a Capital Distribution") do
	visit("/funds/1")
	click_on("Distributions")
	click_on("New Distribution")

	fill_in 'capital_distribution_title', with: 'Sample Distribution Title'
	fill_in 'capital_distribution_gross_amount', with: '100000'
  fill_in 'capital_distribution_cost_of_investment', with: '50000'
  fill_in 'capital_distribution_reinvestment', with: '20000'
  fill_in 'capital_distribution_distribution_date', with: '2024-12-15'
  
  click_link 'Add Distribution Fee'

  select 'Tax fee', from: 'fee_name'

  fill_in 'fee_start_date', with: '2024-12-01'
  fill_in 'fee_end_date', with: '2024-12-31'

  if page.has_css?('#fee_formula')
    check 'fee_formula'
  end

  note = "(capital_commitment.call_fee_cents * 0.5)"
  fill_in 'fee_notes', with: note

  click_button 'Save'
end

Given("there is a AccountEntry for distribution") do
	@fund.account_entries.create!(name: "Tax fee", reporting_date: "2024-12-02", entity_id: @fund.entity_id, entry_type: "Portfolio", capital_commitment_id: CapitalCommitment.first.id, amount_cents: 1000929, entry_type: "Tax")
end

Then('it should create Capital Distribution') do
	sleep(20)
	distribution = CapitalDistribution.first
  expect(distribution.gross_amount_cents).to(eq(0.1e8))
  expect(distribution.cost_of_investment_cents).to(eq(0.5e7))
  expect(distribution.reinvestment_cents).to(eq(0.2e7))
  expect(distribution.capital_distribution_payments.first.json_fields["tax_fee"]).to(eq("₹10,009.29"))
end

Then('the amount payment should be shown on Capital Distribution Payment page') do
  visit('/capital_distribution_payments/1')
  expect(page).to have_content("Fees")
  expect(page).to have_content("Total Amount")
end
