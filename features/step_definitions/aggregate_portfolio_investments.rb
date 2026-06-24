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
	# Use tolerance to handle floating point precision differences
	expect(api.send(key.to_sym).to_d).to be_within(BigDecimal('0.01')).of(value.to_d)
end

# =============================================================================
# Master Fund / Feeder Fund Portfolio Access (policy scope change)
# =============================================================================
#
# These steps support tests for the AggregatePortfolioInvestmentPolicy::Scope
# change that grants investors visibility into master-fund PIs when they have
# access to a feeder fund AND the master fund has show_portfolios = true.
#
# The fund/PI/investor setup itself reuses existing steps ("there is a fund
# ... for the entity", "there are ... portfolio investments ...", "there is
# an existing investor entity ...", "another user is ... investor access to
# the fund") — only the master/feeder relationship and the navigation are
# new, since no existing step links two funds together.

Given('the current fund is the master fund') do
  # Stash the just-created fund (the most recent "there is a fund ... for
  # the entity") as the master, before the next fund-creation step
  # overwrites @fund with the feeder.
  @master_fund = @fund
end

Given('the current fund is a feeder of the master fund') do
  # @fund here is the feeder created by "there is a fund ... for the
  # entity" right after "the current fund is the master fund" ran.
  @fund.update!(master_fund_id: @master_fund.id)
end

When('I view the master fund\'s portfolio investments') do
  visit("/aggregate_portfolio_investments?fund_id=#{@master_fund.id}")
end
