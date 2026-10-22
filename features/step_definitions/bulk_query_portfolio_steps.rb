# Steps for features/fund/bulk_query_portfolio.feature (bulk-path-query-optimisation, phase 6).
# Setup reuses portfolio.rb ("there are {string} portfolio investments {string}", "an aggregate portfolio
# investment should be created") and date_range_sanity.rb ("I import portfolio investments"); counts use
# query_budget_steps.rb.

QUANTITY_COLUMNS = %i[id sold_quantity transfer_quantity net_quantity net_bought_quantity].freeze

Given("I note each portfolio investment's quantities") do
  @noted_quantities = PortfolioInvestment.where(fund_id: @fund.id).order(:id).pluck(*QUANTITY_COLUMNS)
  expect(@noted_quantities).not_to be_empty
end

When('the fund fair value recompute job runs') do
  FundFairValueRecomputeJob.perform_now(@fund.id)
end

# H6: re-valuing with the batch's preloaded sold/transferred quantities gives the same figures as summing each
Then("each portfolio investment's quantities should be unchanged") do
  expect(PortfolioInvestment.where(fund_id: @fund.id).order(:id).pluck(*QUANTITY_COLUMNS)).to eq(@noted_quantities)
end

# E9: an investment with no sales or conversions reads 0 sold and 0 transferred, as an empty SUM does
Then('every bought portfolio investment should have sold and transferred quantity 0') do
  PortfolioInvestment.where(fund_id: @fund.id).buys.find_each do |pi|
    expect([pi.sold_quantity.to_d, pi.transfer_quantity.to_d]).to eq([0, 0])
  end
end

# H10, E13 (phase 8): buys and sells on fixed dates, so a past as-of date falls between them
Given('Gamma holds {int} buys of {int} on {string} and sells of {int} on {string}') do |buys, qty, buy_date, sell_qty, sell_dates|
  buys.times { step %(there are "1" portfolio investments "quantity=#{qty};investment_date=#{buy_date}") }
  sell_dates.split(",").map(&:strip).each do |date|
    step %(there are "1" portfolio investments "quantity=-#{sell_qty};investment_date=#{date}")
  end
  @gamma_buys = PortfolioInvestment.where(fund_id: @fund.id).buys.order(:id).to_a
end

# A conversion row out of the first buy. Created directly: the preload and the live sum read the same row, and
# that is what is compared - the conversion service's knock-on investments are not under test here.
Given('{int} units of the first buy were converted on {string}') do |qty, date|
  to_instrument = @investment_instrument.dup.tap { |i| i.name = "#{@investment_instrument.name} Pref" }
  to_instrument.save!
  conversion = StockConversion.new(entity: @entity, fund: @fund, from_portfolio_investment: @gamma_buys.first,
                                   from_instrument: @investment_instrument, to_instrument:,
                                   from_quantity: qty, to_quantity: qty, conversion_date: Date.parse(date))
  conversion.save!(validate: false)
end

# E13: the sale dated earliest becomes proforma after it was attributed. net_quantity_on leaves it out: the
# sold_pi join carries PortfolioInvestment's default scope (proforma = FALSE) in its ON clause, which the
# merged include_proforma does not remove - the preload builds the same join, so it must leave it out too
Given('the earliest sale is proforma') do
  PortfolioInvestment.where(fund_id: @fund.id).sells.order(:investment_date).first.update_columns(proforma: true)
end

When('the aggregate is valued as of {string}') do |date|
  @as_of_date = Date.parse(date)
  @as_of_api = AggregatePortfolioInvestment.find_by!(fund_id: @fund.id).as_of(@as_of_date)
end

# Each buy's as-of figures from the aggregate (preloaded) against the same buy computed alone (live SUMs)
Then("each buy's as-of quantities and values should match the live calculation") do
  preloaded = @as_of_api.portfolio_investments.select(&:buy?).index_by(&:id)
  expect(preloaded.keys).to match_array(@gamma_buys.map(&:id))
  @gamma_buys.each do |buy|
    live = PortfolioInvestment.find(buy.id).as_of(@as_of_date)
    got = preloaded.fetch(buy.id)
    %i[sold_quantity transfer_quantity net_quantity net_bought_quantity fmv_cents instrument_currency_fmv_cents].each do |attr|
      expect(got.public_send(attr)).to eq(live.public_send(attr)), "#{attr} of buy #{buy.id}"
    end
    expect(got.net_quantity_on(@as_of_date)).to eq(live.net_quantity_on(@as_of_date))
  end
end

# E13: net_quantity_on as of the date, live and from the aggregate's preload
Then("the first buy's net quantity on that date should be {int}") do |qty|
  expect(PortfolioInvestment.find(@gamma_buys.first.id).net_quantity_on(@as_of_date)).to eq(qty)
  got = @as_of_api.portfolio_investments.find { |pi| pi.id == @gamma_buys.first.id }
  expect(got.net_quantity_on(@as_of_date)).to eq(qty)
end
