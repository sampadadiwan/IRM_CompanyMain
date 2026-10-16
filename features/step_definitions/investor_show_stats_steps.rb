# Steps for features/core/investor_show_stats.feature (investors/_show_stats)

Given('there is a stakeholder with commitments of {string} INR and {string} USD') do |inr, usd|
  # Investor.create! rather than the :investor factory, whose defaults sample random entities
  @investor = Investor.create!(entity_id: @entity.id, investor_name: "Stats LP",
                               primary_email: "stats.lp@example.com", category: "LP")
  { "INR" => inr, "USD" => usd }.each do |currency, amount|
    fund = FactoryBot.create(:fund, entity: @entity, currency: currency)
    commitment = FactoryBot.create(:capital_commitment, fund: fund, entity: @entity, investor: @investor)
    # Pin the amounts the card sums (the factory's folio amount is random and callbacks derive the rest)
    commitment.update_columns(committed_amount_cents: amount.to_i * 100, call_amount_cents: 0,
                              collected_amount_cents: 0, distribution_amount_cents: 0)
  end
end

Given('there is a portfolio company stakeholder') do
  @investor = Investor.create!(entity_id: @entity.id, investor_name: "Stats Portco",
                               primary_email: "stats.portco@example.com", category: "Portfolio Company")
end

Given('the stakeholder has {int} open task(s)') do |count|
  count.times do |i|
    Task.create!(entity: @entity, for_entity: @entity, owner: @investor, user: @user,
                 details: "Stats task #{i}", completed: false)
  end
end

When("I visit the stakeholder's page") do
  visit(investor_path(@investor))
end

# The card is the NumberStatsComponent whose subtitle is the given label
def stat_card(label)
  find(".stat-card-accent", text: label)
end

Then('the {string} stat card shows {string}') do |label, value|
  expect(stat_card(label)).to have_content(value)
end

Then('the {string} stat card shows {string} and {string}') do |label, first, second|
  card = stat_card(label)
  expect(card).to have_content(first)
  expect(card).to have_content(second)
end

Then('I should see stat cards {string}') do |labels|
  labels.split(",").map(&:strip).each { |label| expect(page).to have_css(".stat-card-accent", text: label) }
end

Then('I should not see a {string} stat card') do |label|
  expect(page).to have_no_css(".stat-card-accent", text: label)
end

When('I click the {string} stat card') do |label|
  stat_card(label).click
end

# The card links to ?tab=<pane>; the tabs controller opens that pane on load
Then('the {string} tab is open') do |pane|
  expect(page).to have_current_path(/tab=#{pane}/)
  expect(page).to have_css("##{pane}.active")
end
