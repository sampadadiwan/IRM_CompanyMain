# Steps for features/deal/bulk_query_deal_steps.feature (round 3 query fixes D1, D2 - tmp/query_fixes_round3.md).
# The budgets themselves use the generic steps in query_budget_steps.rb.

Given('the deal has {int} investors with no steps yet') do |count|
  count.times do
    steps %(Given there is an existing investor "")
    DealInvestor.create!(deal: @deal, investor: @investor, entity_id: @deal.entity_id, status: "Active",
                         primary_amount_cents: 100_000_00, pre_money_valuation_cents: 0, tier: "Tier 2")
  end
  # Fixture setup: creating an investor queues its own step generation; clear any steps it made so the
  # generation below starts from investors with none
  DealActivity.where(deal_id: @deal.id).where.not(deal_investor_id: nil).delete_all
  expect(@deal.deal_investors.count).to eq(count)
end

When("the deal's steps are generated for its investors") do
  GenerateDealActivitiesJob.perform_now(@deal.id, "Deal")
end

When('a template {string} is inserted at position {int} of the deal') do |title, position|
  # acts_as_list shifts the templates at and after this position down by one
  DealActivity.create!(deal: @deal, entity_id: @deal.entity_id, title:, days: 1, sequence: position)
end

Then('every investor of the deal has the template steps, numbered {int} to {int} in template order') do |first, last|
  templates = DealActivity.templates(@deal).to_a
  expect(templates.map(&:sequence)).to eq((first..last).to_a)
  @deal.deal_investors.each do |deal_investor|
    investor_steps = DealActivity.where(deal_id: @deal.id, deal_investor_id: deal_investor.id).order(:sequence).to_a
    expect(investor_steps.map(&:template_id)).to eq(templates.map(&:id)), "#{deal_investor.investor_name}: steps follow the templates"
    expect(investor_steps.map(&:sequence)).to eq((first..last).to_a), "#{deal_investor.investor_name}: numbered without gaps or repeats"
  end
end

Then("the cloned deal's template steps are numbered {int} to {int} in the source deal's order") do |first, last|
  cloned = DealActivity.templates(@cloned_deal).to_a
  expect(cloned.map(&:sequence)).to eq((first..last).to_a)
  expect(cloned.map(&:title)).to eq(DealActivity.templates(@deal).map(&:title))
end
