When('I create a Capital Call') do
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
  sleep(5)
end

Given("it should create Capital Remittances according to the close percentage") do
	expect(CapitalRemittance.first.percentage).to(eq("10".to_d))
	expect(CapitalRemittance.second.percentage).to(eq("20".to_d))
end