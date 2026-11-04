# Steps for features/fund/portfolio_stats_widget_settings.feature
# (openspec/changes/fix-portfolio-dashboard-widgets-2/design.md#worked-examples)

Given('view caching is on') do
  @stats_previous_cache_store = ActionController::Base.cache_store
  @stats_previous_perform_caching = ActionController::Base.perform_caching
  ActionController::Base.cache_store = ActiveSupport::Cache::MemoryStore.new
  ActionController::Base.perform_caching = true
end

After do
  if @stats_previous_cache_store
    ActionController::Base.cache_store = @stats_previous_cache_store
    ActionController::Base.perform_caching = @stats_previous_perform_caching
    @stats_previous_cache_store = nil
  end
end

Given('the {string} widget on the {string} has settings {string}') do |widget_name, dashboard_name, metadata|
  widget = DashboardWidget.find_or_initialize_by(entity_id: @user.entity_id, dashboard_name:, widget_name:, name: "Default")
  widget.update!(enabled: true, position: 1, size: "XL", tags: widget_name, metadata:)
  @stats_widget = widget
end

Given('the firm has exchange rates between {string} and {string}') do |foreign, local|
  ExchangeRate.create!(entity_id: @user.entity_id, from: foreign, to: local, rate: 80, as_of: Date.new(2024, 1, 1))
  ExchangeRate.create!(entity_id: @user.entity_id, from: local, to: foreign, rate: 0.0125, as_of: Date.new(2024, 1, 1))
end

Given("the firm's tracking currency is {string}") do |currency|
  @user.entity.update_column(:tracking_currency, currency)
end

When('I open the company dashboard of {string}') do |name|
  company = Investor.find_by!(entity_id: @user.entity_id, investor_name: name)
  visit("/investors/#{company.id}/dashboard")
end

When('I open the {string} of fund {string}') do |dashboard_name, fund_name|
  visit(dashboard_fund_path(lp_fund(fund_name), dashboard_name:))
end

When('I open the Portfolio Investments page of fund {string}') do |fund_name|
  visit(aggregate_portfolio_investments_path(fund_id: lp_fund(fund_name).id))
end

def stats_widget_cards
  container = find("##{@stats_widget.widget_name.parameterize.underscore}_#{@stats_widget.position}")
  container.all(".stat-card-accent")
end

def stats_widget_card(label)
  stats_widget_cards.find { |card| card.find(".card-subtitle").text.strip == label } ||
    raise("No stats card labelled #{label}")
end

Then('the stats cards should be labelled {string}') do |labels|
  expect(stats_widget_cards.map { |card| card.find(".card-subtitle").text.strip }).to eq(labels.split(",").map(&:strip))
end

Then('the stats card {string} should show {string}') do |label, text|
  expect(stats_widget_card(label).find("h2, h3", match: :first).text).to include(text)
end

Then('the stats card {string} should show {int} decimals') do |label, decimals|
  amount = stats_widget_card(label).find("h2, h3", match: :first).text
  shown = amount[/\.(\d+)/, 1].to_s.length
  expect(shown).to eq(decimals)
end

Then('the stats card widths should be {string}') do |widths|
  container = find("##{@stats_widget.widget_name.parameterize.underscore}_#{@stats_widget.position}")
  styles = container.all(".stat-card-col").map { |col| col[:style].to_s[/--stat-card-width:\s*([\d.]+%)/, 1] }
  expect(styles).to eq(widths.split(",").map(&:strip))
end

Then('the stats currency drop-down should have {string} selected') do |currency|
  expect(find('select[data-portfolio-stats-currency-target="select"]')).to match_selector(:select, selected: currency)
end

Then('the stats currency drop-down should list {string}') do |currencies|
  expect(find('select[data-portfolio-stats-currency-target="select"]')).to match_selector(:select, options: currencies.split(",").map(&:strip))
end

When('I pick {string} in the stats currency drop-down') do |currency|
  find('select[data-portfolio-stats-currency-target="select"]').select(currency)
end

Then('the page stats cards should include {string}') do |labels|
  shown = all(".stat-card-accent .card-subtitle").map { |label| label.text.strip }
  expect(shown).to include(*labels.split(",").map(&:strip))
end

Then('the page stats cards should not include {string}') do |label|
  shown = all(".stat-card-accent .card-subtitle").map { |subtitle| subtitle.text.strip }
  expect(shown).not_to include(label)
end
