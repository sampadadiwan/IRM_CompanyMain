# frozen_string_literal: true

# Fund Ratios Steps
Given('there is a fund ratio {string} for the fund') do |attributes|
  @fund_ratio = FactoryBot.create(
    :fund_ratio,
    entity: @fund.entity,
    fund: @fund,
    owner: @fund,
    end_date: Date.current,
    latest: true
  )
  key_values(@fund_ratio, attributes)
  @fund_ratio.save!

  # Ensure Fund Ratios widget is configured for the portfolio company dashboard
  unless DashboardWidget.exists?(
    entity_id: @fund.entity_id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Fund Ratios',
    name: 'Default'
  )
    DashboardWidget.create!(
      entity_id: @fund.entity_id,
      dashboard_name: 'Portfolio Company Dashboard',
      widget_name: 'Fund Ratios',
      name: 'Default',
      enabled: true,
      position: 1,
      size: 'XL',
      tags: 'Fund Ratios',
      metadata: '{condensed: true, chart: false, scenarios: true}'
    )
  end
end

When('I visit the portfolio company dashboard') do
  # Visit the portfolio company dashboard page where all three widgets are shown
  visit "/investors/#{@portfolio_company.id}/dashboard"
  sleep(1) # Give time for the page to load
end

Then('I should see a select element for currency filtering') do
  expect(page).to have_select('metrics_filter_select', visible: true)
end

Then('the currency dropdown should have option {string}') do |currency|
  expect(page).to have_select('metrics_filter_select', with_options: [currency])
end

Then('I should not see a currency dropdown for fund ratios') do
  expect(page).not_to have_select('metrics_filter_select', visible: true)
end

# Portfolio Company Steps
Given('there is a portfolio investment for the fund {string}') do |attributes|
  pi = FactoryBot.build(
    :portfolio_investment,
    entity: @fund.entity,
    fund: @fund,
    portfolio_company: @portfolio_company,
    investment_instrument: @investment_instrument,
    investment_date: Date.current
  )
  key_values(pi, attributes)

  # Use the service to create portfolio investment (handles validations and aggregate creation)
  result = PortfolioInvestmentCreate.wtf?(portfolio_investment: pi)
  result.success?.should == true

  @portfolio_investment = pi

  # Ensure Portfolio Stats widget is configured
  unless DashboardWidget.exists?(
    entity_id: @fund.entity_id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Portfolio Stats',
    name: 'Default'
  )
    DashboardWidget.create!(
      entity_id: @fund.entity_id,
      dashboard_name: 'Portfolio Company Dashboard',
      widget_name: 'Portfolio Stats',
      name: 'Default',
      enabled: true,
      position: 2,
      size: 'XL',
      tags: 'Portfolio Stats',
      metadata: "{tracking_currency: true}"
    )
  end

  # Create a valuation for the portfolio investment
  @valuation = FactoryBot.create(
    :valuation,
    entity: @fund.entity,
    owner: @portfolio_investment,
    investment_instrument: @investment_instrument,
    valuation_date: Date.current,
    fmv_cents: @portfolio_investment.base_amount_cents
  )
end

Then('I should see a select element for portfolio currency') do
  # The portfolio stats currency dropdown
  expect(page).to have_css('select[data-portfolio-stats-currency-target="select"]', visible: true)
end

Then('I should see a select element for valuation currency') do
  # The valuation time series currency dropdown
  expect(page).to have_css('select[id^="valuation_currency_select"]', visible: true)
end

# Valuation Steps
Given('there is a valuation with multiple currencies for the investment instrument') do
  @valuation = FactoryBot.create(
    :valuation,
    entity: @entity,
    owner: @portfolio_company,
    investment_instrument: @investment_instrument,
    valuation_date: Date.current
  )

  # Add custom fields with different currencies
  @valuation.update(
    json_fields: {
      'fmv' => 1000000.0,
      'fmv_usd' => 1200000.0,
      'fmv_inr' => 90000000.0,
      'equity' => 500000.0,
      'equity_usd' => 600000.0
    }
  )

  # Create a Report to show valuations with time_series
  @valuation_report = Report.create!(
    entity: @entity,
    user: @user,
    name: 'Portfolio Company Valuations',
    curr_role: 'company_admin',
    category: 'Valuations',
    url: '/valuations?owner_id={investor_id}&owner_type=Investor&timeseries=true&filter=true'
  )

  # Ensure Portfolio Company Report widget is configured
  unless DashboardWidget.exists?(
    entity_id: @entity.id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Portfolio Company Report',
    name: 'Default'
  )
    DashboardWidget.create!(
      entity_id: @entity.id,
      dashboard_name: 'Portfolio Company Dashboard',
      widget_name: 'Portfolio Company Report',
      name: 'Default',
      enabled: true,
      position: 3,
      size: 'XL',
      tags: 'Portfolio Company Report',
      metadata: "{report_id: #{@valuation_report.id}}"
    )
  end
end

Given('there is a valuation with only entity currency for the investment instrument') do
  @valuation = FactoryBot.create(
    :valuation,
    entity: @entity,
    owner: @portfolio_company,
    investment_instrument: @investment_instrument,
    valuation_date: Date.current,
    json_fields: {
      'fmv' => 1000000.0,
      'equity' => 500000.0
    }
  )
end

When('I visit the valuations time series page') do
  # Visit the portfolio company page which contains the time series partial
  visit portfolio_company_path(@portfolio_company)
  # Or visit the investment instrument page that shows valuations
  # visit investment_instrument_path(@investment_instrument)
end
