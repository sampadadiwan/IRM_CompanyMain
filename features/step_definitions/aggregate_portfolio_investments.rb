Then("2 aggregate portfolio investments should be created") do
	expect(AggregatePortfolioInvestment.count).to(eq(2))
	visit('/aggregate_portfolio_investments')
	#sleep(1)
	within('tbody') do
    expect(page).to have_selector('tr', count: 2)
  end
end

Then("I search for Merger") do
	AggregatePortfolioInvestmentIndex.import!
	fill_in 'search_input', with: "Merger"
	find('input#search_input').send_keys(:enter)
	#sleep(1)
	within('tbody') do
    expect(page).to have_selector('tr', count: 1)
  end
end

Given('the api {string} is {string}') do |key, value|
	api = AggregatePortfolioInvestment.last
	puts "Checking #{key} is #{value}"
	# binding.pry if api.send(key.to_sym).to_d != value.to_d
	api.send(key.to_sym).to_d.should eq(value.to_d)
end