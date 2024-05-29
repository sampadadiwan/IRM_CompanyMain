Then("2 aggregate portfolio investments should be created") do
	expect(AggregatePortfolioInvestment.count).to(eq(2))
	visit('/aggregate_portfolio_investments')
	sleep(1)
	within('tbody') do
    expect(page).to have_selector('tr', count: 2)
  end
end

Then("I search for Merger") do
	AggregatePortfolioInvestmentIndex.import!
	fill_in 'dt-search-0', with: "Merger"
	find('#dt-search-0').send_keys(:enter)
	sleep(1)
	within('tbody') do
    expect(page).to have_selector('tr', count: 1)
  end
end