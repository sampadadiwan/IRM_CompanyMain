# frozen_string_literal: true

# This is a helper to create a valid portfolio investment associated with the given
# portfolio company, investment instrument, entity, and fund.
# AggregatedPortfolioInvestment is created here
def create_valid_portfolio_investment!(
  portfolio_company:,
  investment_instrument:,
  entity:,
  fund:
)
  aggregate = AggregatePortfolioInvestment.find_or_create_by!(
    fund_id: fund.id,
    portfolio_company_id: portfolio_company.id,
    entity_id: entity.id,
    investment_instrument_id: investment_instrument.id
  ) do |agg|
    agg.form_type = entity.form_types.find_by(name: "AggregatePortfolioInvestment")
  end

  PortfolioInvestment.create!(
    portfolio_company: portfolio_company,
    portfolio_company_name: portfolio_company.investor_name,
    investment_instrument: investment_instrument,
    entity: entity,
    fund: fund,
    aggregate_portfolio_investment: aggregate,

    investment_date: Date.today,
    quantity: 100,

    base_amount_cents: 1_000_000_00,
    ex_expenses_base_amount_cents: 1_000_000_00,
    amount_cents: 1_000_000_00,
    net_amount_cents: 1_000_000_00,
    net_bought_amount_cents: 1_000_000_00,

    notes: "Cucumber generated investment"
  )
end

When("I visit the Aggregated Portfolio Dashboard widget page") do
  visit new_dashboard_widget_path
end
When("I click on New Dashboard Widgets") do
  click_button "New Dashboard Widget"
end
When("I fill the new dashboard widget form with data 1") do
  select "Aggregated Portfolio Dashboard", from: "dashboard_name"
  select "Stats", from: "widget_name"
  fill_in "dashboard_widget_tags", with: "test_cross_portfolio_stats"
  select "XL", from: "dashboard_widget_size"
  fill_in "dashboard_widget_position", with: 1
  fill_in "dashboard_widget_metadata", with: "{title:'Stats', currency: 'INR', force_units: 'crores', decimals: 2}"
  check "dashboard_widget_enabled"
  check "dashboard_widget_show_menu"
  click_button "Save"
end

When("I fill the new dashboard widget form with data 4") do
  select "Aggregated Portfolio Dashboard", from: "dashboard_name"
  select "Aggre. Portfolio Investments", from: "widget_name"
  fill_in "dashboard_widget_tags", with: "test_agg_portfolio_investments"
  select "XL", from: "dashboard_widget_size"
  fill_in "dashboard_widget_position", with: 4
  fill_in "dashboard_widget_metadata", with: "{title:'Portfolio Investments', currency: 'INR', decimals: 2}"
  check "dashboard_widget_enabled"
  check "dashboard_widget_show_menu"
  click_button "Save"
end
When("I fill the new dashboard widget form with data 2") do
  select "Aggregated Portfolio Dashboard", from: "dashboard_name"
  select "Company Charts", from: "widget_name"
  fill_in "dashboard_widget_tags", with: "test_company_charts_bought_amount"
  select "M", from: "dashboard_widget_size"
  fill_in "dashboard_widget_position", with: 2
  fill_in "dashboard_widget_metadata", with: "{title:'Company-Bought Amount', currency: 'INR', plot: 'bought_amount', show_portfolio_company_wise: true, show_table: true}"
  check "dashboard_widget_enabled"
  check "dashboard_widget_show_menu"
  click_button "Save"
end
When("I fill the new dashboard widget form with data 3") do
  select "Aggregated Portfolio Dashboard", from: "dashboard_name"
  select "Company Charts", from: "widget_name"
  fill_in "dashboard_widget_tags", with: "test_company_charts_sector_fmv"
  select "M", from: "dashboard_widget_size"
  fill_in "dashboard_widget_position", with: 3
  fill_in "dashboard_widget_metadata", with: "{title:'Sector-FMV', currency: 'INR', plot: 'fmv', show_sector_wise: true, show_table: true}"
  check "dashboard_widget_enabled"
  check "dashboard_widget_show_menu"
  click_button "Save"
end
When("I fill the new dashboard widget form with data 5") do
  select "Aggregated Portfolio Dashboard", from: "dashboard_name"
  select "Fund Ratios", from: "widget_name"
  fill_in "dashboard_widget_tags", with: "test_fund_ratios"
  select "XL", from: "dashboard_widget_size"
  fill_in "dashboard_widget_position", with: 5
  fill_in "dashboard_widget_metadata", with: "{show_table: true, show_chart: true, ratio_names: ['Gross Portfolio IRR', 'Gross Portfolio MOIC'], titles: ['Gross Portfolio IRR', 'Gross Portfolio MOIC'],chart_colors: ['#00c49a', '#ff8042']}"
  check "dashboard_widget_enabled"
  check "dashboard_widget_show_menu"
  click_button "Save"
end
Then("the dashboard widget must be created") do
  expect(page).to have_content("Dashboard widget was successfully created.")
end
When('I navigate to the cross portfolio dashboard') do
  visit investors_path(
    multi_portfolio_dashboard: true,
    q: {
      c: {
        '0' => {
          a: {
            '0' => { name: 'category' }
          },
          p: 'eq',
          v: {
            '0' => { value: 'Portfolio Company' }
          }
        }
      }
    }
  )
end
Given('the portfolio companies belong to sectors {string}') do |sectors|
  all_sectors = sectors.split(',').map(&:strip)
  raise 'Need at least one sector' if all_sectors.empty?

  Investor.portfolio_companies.find_each do |company|
    company.sector = all_sectors.sample
    company.save!
  end
end

Given('fund ratio {string} for fund {string} exist') do |ratio_name, fund_name|
  fund = Fund.includes(:entity).find_by!(name: fund_name)

  # Create some dummy ratios for the fund

    FundRatio.create!(
      entity: fund.entity,
      fund: fund,
      owner: fund,
      name: ratio_name,
      end_date: Date.today - (6).months,
      latest: true,
      value: rand(5.0..25.0).round(2)
    )
end

Then('the fund ratios for funds with tables and chart are shown') do
  expect(page).to have_content('Gross Portfolio IRR')
  expect(page).to have_content('Gross Portfolio MOIC')
end

Then('the fund ratios fetched for funds {string} should be correct and latest') do |funds|
  fund_names = funds.split(',').map(&:strip)
  fund_ids = Fund.where(name: fund_names).pluck(:id)

  ratios = FundRatio.latest.where(
    owner_type: 'Fund',
    owner_id: fund_ids,
    name: ['Gross Portfolio IRR', 'Gross Portfolio MOIC']
  )
  expect(page).to have_content(ratios[0].display_value)
  expect(page).to have_content(ratios[1].display_value)
  expect(page).to have_content(ratios[2].display_value)
  expect(page).to have_content(ratios[3].display_value)
end
Then('I should see the cross portfolio dashboard page') do
  expect(page).to have_content('Multi-Portfolio Filter')
  expect(page).to have_field('Funds')
  expect(page).to have_field('Tags')
  expect(page).to have_field('Sectors')
end

# ------------------------
# FILTER STEPS
# ------------------------

When('I apply the fund filter {string}') do |funds|
  Array(funds.split(',')).each do |fund_name|
    # Find the select associated with the "Fund" label

    fund_select = find(
      :xpath,
      "//label[normalize-space(text())='Funds']/following::*[self::select or self::div][1]"
    )

    within(fund_select) do
      select fund_name.strip
    end
  end
end


When('I apply the tag filter {string}') do |tags|
   tag_select = find(
      :xpath,
      "//label[normalize-space(text())='Tags']/following::*[self::select or self::div][1]"
    )
  Array(tags.split(',')).each do |tag|
    within(tag_select) do
      select tag.strip, from: 'Tags'
    end
  end
end

When('I apply the sector filter {string}') do |sectors|
  Array(sectors.split(',')).each do |sector|
    sector_select = find(
      :xpath,
      "//label[normalize-space(text())='Sectors']/following::*[self::select or self::div][1]"
    )
    within(sector_select) do
      select sector.strip, from: 'Sectors'
    end
  end
end

When('I clear all dashboard filters') do
  click_button 'Clear Filters'
end

# ------------------------
# DATA SETUP STEPS
# ------------------------

Given('the portfolio companies are tagged randomly from {string}') do |tags|
  all_tags = tags.split(',').map(&:strip)
  raise 'Need at least 2 tags to randomize' if all_tags.size < 2

  Investor.portfolio_companies.find_each do |company|
    # pick between 2 and all available tags
    random_count = rand(2..all_tags.size)

    selected_tags = all_tags.sample(random_count)

    company.tag_list = selected_tags.join(', ')
    company.save!
  end
end

Given('the portfolio companies are tagged with {string}') do |tag|
  Investor.portfolio_companies.find_each do |company|
    company.tag_list = tag
    company.save!
  end
end
Given("a portfolio company with instrument exists") do
  fund = create(:fund)
  entity = fund.entity

  portfolio_company = create(
    :investor,
    entity: entity,
    category: "Portfolio Company"
  )

  investment_instrument = create(
    :investment_instrument,
    portfolio_company: portfolio_company
  )

  @fund = fund
  @entity = entity
  @portfolio_company = portfolio_company
  @investment_instrument = investment_instrument
end


Given("investment instruments exist for each portfolio company") do
  @investment_instruments = []

  @portfolio_companies.each do |company|
    @investment_instruments << FactoryBot.create(
      :investment_instrument,
      portfolio_company: company,
      entity: company.entity
    )
  end
end

Given("portfolio investments are created") do
  @portfolio_investments = []

  @investment_instruments.each do |instrument|
    @portfolio_investments << create_valid_portfolio_investment!(
      portfolio_company: instrument.portfolio_company,
      investment_instrument: instrument,
      entity: instrument.entity,
      fund: Fund.find([1, 2].sample)
    )
  end
  @total_bought_cents = @portfolio_investments.sum(&:net_bought_amount_cents)

end
Then("All calculations should be correct") do
  expect(page).to have_content(
    money_to_currency(Money.new(@total_bought_cents,"INR"), {force_units: 'crores'}, decimals:2)
  )
end
Given("portfolio company is added to list of companies") do
  @portfolio_companies ||= []
  @portfolio_companies << @portfolio_company
end




Given('the portfolio company belong to sectors {string}') do |sectors|
  @sectors = sectors.split(',').map(&:strip)

  Investor.portfolio_companies.find_each.with_index do |company, index|
    company.update!(
      sector: @sectors[index % @sectors.size]
    )
  end
end

Given('investments exist for tag {string} with amount {float}') do |tag, amount|
  Investor.portfolio_companies.with_tag_list(tag).each do |company|
    instrument = FactoryBot.create(
      :investment_instrument,
      portfolio_company: company,
      entity: company.entity
    )

    create_valid_portfolio_investment!(
      portfolio_company: company,
      investment_instrument: instrument,
      entity: company.entity,
      fund: Fund.first
    ).update!(
      amount_cents: amount * 100,
      net_amount_cents: amount * 100
    )
  end
end

Given('I calculate expected bought amount for tag {string}') do |tag|
  @expected_bought_cents =
    Investor.portfolio_companies
            .with_tag_list(tag)
            .joins(:portfolio_investments)
            .sum(:amount_cents)
end

When('I visit the cross portfolio dashboard with tags {string}') do |tags|
  visit investors_path(
    multi_portfolio_dashboard: true,
    tag_list: tags.split(',').map(&:strip)
  )
end

Then('the Bought Amount stat should be correct') do

  expect(page).to have_content(
    money_to_currency(Money.new(@expected_bought_cents,"INR"),{force_units: 'crores' }, decimals:2)
  )
end