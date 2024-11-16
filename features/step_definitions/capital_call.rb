When('I create a Capital Call with percentage of commitment') do
	visit("/funds/1")
	sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	sleep(0.2)
	click_on("New Call")
	sleep(0.2)
	fill_in 'capital_call_name', with: 'Demo call'
	sleep(1)
	fill_in "capital_call[close_percentages][First Close]", with: "10"
	fill_in "capital_call[close_percentages][Second Close]", with: "20"
  find('input[name="capital_call[call_date]"]').set('13/09/2024')
  find('input[name="capital_call[due_date]"]').set('13/11/2024')
  allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
  click_on('Save')
  sleep(2)
end

When("I create a Capital Call with upload call basis") do
	allow(UpdateDocumentFolderPathJob).to receive(:perform_later).and_return(nil)
	visit("/funds/1")
	sleep(0.5)
	find('a.nav-link[href="#capital-calls-tab"]').click
	sleep(0.2)
	click_on("New Call")
	sleep(0.2)
	fill_in 'capital_call_name', with: 'Upload capital call'
	sleep(1)
	select 'Upload', from: 'capital_call[call_basis]'
	fill_in 'Series A_price', with: '1'
	click_on('Save')
	sleep(2)
end

Given("it should create a Capital Call with given data") do
	capital_call = CapitalCall.last
	expect(capital_call.name).to(eq("Upload capital call"))
	expect(capital_call.call_basis).to(eq("Upload"))
	expect(capital_call.fund_closes).to_not be_present
end

Given("it should create Capital Remittances according to the close percentage") do
	expect(CapitalRemittance.pluck(:percentage)).to match_array([BigDecimal("10"), BigDecimal("20")])
end

Given('the remittances has some units already allocated') do
  capital_remittance = CapitalRemittance.last
  fund_unit = CapitalRemittance.last.fund_units.build(
    fund_id:capital_remittance.capital_commitment.fund_id,
    capital_commitment_id: capital_remittance.capital_commitment.id,
    investor_id: capital_remittance.capital_commitment.investor_id,
    entity_id: capital_remittance.entity_id,
    unit_type: "Series A",
    quantity: 100.0,
    price: 50.0,
    premium: 10.0,
    issue_date: Date.today,
    reason: "Initial Allocation"
  )
  fund_unit.save!
end

And("error email for fund units already allocated should be sent") do
	current_email = open_email(User.first.email)
	expect(current_email).to have_content("Fund Units already allocated")
end