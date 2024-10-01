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
  click_on('Save')
  sleep(2)
end

When("I create a Capital Call with upload call basis") do
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
