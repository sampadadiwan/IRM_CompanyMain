# Steps for features/fund/portfolio_investment_duplicate.feature — the duplicate-sell
# confirmation flow (portfolio_investment_duplicate_check_controller.js +
# PortfolioInvestmentsController#check_duplicate_sell / PortfolioInvestment.matching_sells).
#
# "Given I go to API show page" / "Given I click on ..." (shared step) already prefill the
# new-PI form's portfolio company and instrument from the aggregate PI page's "New Investment"
# link, same as the existing "I fill in the new investment form" steps in portfolio.rb.

Given('I fill in the new investment form with amount {string} quantity {string} on {string}') do |amount, quantity, date|
  fill_in("portfolio_investment_investment_date", with: Date.parse(date))
  fill_in("portfolio_investment_ex_expenses_base_amount", with: amount)
  fill_in("portfolio_investment_quantity", with: quantity)
end

Then('I should see the duplicate investment confirmation with used ref ids {string}') do |ref_ids|
  # The check is an async fetch triggered on submit, so give it a moment to land
  expect(page).to have_content(
    "A portfolio investment with the same date, quantity, and amount already exists. " \
    "To save this as a separate transaction, please enter a Ref ID different from the original.",
    wait: 10
  )
  expect(page).to have_content("Already used for this transaction: #{ref_ids}")
end

When('I confirm the duplicate with ref id {string}') do |ref_id|
  fill_in("piDuplicateRefId", with: ref_id)
  click_on("Yes, Save Anyway")
end

Then('I should see the duplicate ref id error') do
  expect(page).to have_content("Enter a Ref ID different from the one(s) already used.")
end

Then('I should not see the duplicate investment confirmation') do
  expect(page).not_to have_content("A portfolio investment with the same date, quantity, and amount already exists")
end

Then('there should be {string} sell portfolio investments with quantity {string}') do |count, quantity|
  PortfolioInvestment.sells.where(quantity: quantity.to_d).count.should == count.to_i
end

Then('the most recently created sell should have ref_id {string}') do |ref_id|
  PortfolioInvestment.sells.order(:id).last.ref_id.should == ref_id.to_i
end

# NOTE: deliberately not reusing the shared "there must be {string} portfolio attributions
# created" step (portfolio.rb) here — it compares each attribution's sold_pi.cost_of_sold_cents
# against the SUM of quantity*cost across every PortfolioAttribution row in the test, which
# only holds when there's a single sell PI in play. This scenario creates two separate sells
# against the same buy lot, so each sell's own gain must be checked against its own attribution.
Then('each sell should have the correct realized gain and the buy lot should not be over-allocated') do
  attributions = PortfolioAttribution.all.to_a
  attributions.each do |pa|
    pa.sold_pi.sell?.should == true
    pa.cost_of_sold_cents.should == pa.quantity * pa.bought_pi.cost_cents
    pa.sold_pi.gain_cents.should == pa.sold_pi.amount_cents + pa.sold_pi.cost_of_sold_cents
  end

  buy = PortfolioInvestment.buys.first
  buy.sold_quantity.should == attributions.sum(&:quantity)
  buy.net_quantity.should == buy.quantity + buy.sold_quantity
  (buy.net_quantity >= 0).should == true
end
