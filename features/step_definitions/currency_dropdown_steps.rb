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
      metadata: '{condensed: true, chart: false, scenarios: true, show_currency_filter: false}'
    )
  end
end

Given('the Fund Ratios widget has metadata {string}') do |metadata|
  widget = DashboardWidget.find_or_initialize_by(
    entity_id: @fund.entity_id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Fund Ratios',
    name: 'Default'
  )

  widget.assign_attributes(
    enabled: true,
    position: 1,
    size: 'XL',
    tags: 'Fund Ratios',
    metadata: metadata
  )
  widget.save!
end

When('I visit the portfolio company dashboard') do
  # Visit the portfolio company dashboard page where all three widgets are shown
  visit "/investors/#{@portfolio_company.id}/dashboard"
  sleep(2) # Give time for the page to load and turbo frames to render
end

Then('I should see a currency dropdown for fund ratios') do
  # The fund ratios currency dropdown selector
  expect(page).to have_select('metrics_filter_select', visible: true)
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
    investment_date: Date.current,
    quantity: 100  # Ensure it's a buy, not a sell
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
      metadata: "{show_currency_filter: false}"
    )
  end

  # Create a valuation for the portfolio investment
  # Valuations use per_share_value_cents or store values in json_fields
  @valuation = FactoryBot.create(
    :valuation,
    entity: @fund.entity,
    owner: @portfolio_investment,
    investment_instrument: @investment_instrument,
    valuation_date: Date.current
  )
end

Given('the Portfolio Stats widget has metadata {string}') do |metadata|
  widget = DashboardWidget.find_or_initialize_by(
    entity_id: @fund.entity_id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Portfolio Stats',
    name: 'Default'
  )

  widget.assign_attributes(
    enabled: true,
    position: 2,
    size: 'XL',
    tags: 'Portfolio Stats',
    metadata: metadata
  )
  widget.save!
end

Then('I should see a currency dropdown for portfolio stats') do
  # The portfolio stats currency dropdown
  expect(page).to have_css('select[data-portfolio-stats-currency-target="select"]', visible: true)
end

Then('I should not see a currency dropdown for portfolio stats') do
  # The portfolio stats currency dropdown should not be visible
  expect(page).not_to have_css('select[data-portfolio-stats-currency-target="select"]', visible: true)
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
  @valuation_report = Report.find_or_create_by!(
    entity: @entity,
    name: 'Valuation Report',
    curr_role: 'company_admin',
    category: 'Valuation'
  ) do |report|
    report.user = @user
    report.url = "/valuations?q[c][0][a][0][name]=owner_id&q[c][0][p]=eq&q[c][0][v][0][value]=#{@portfolio_company.id}&q[c][1][a][0][name]=owner_type&q[c][1][p]=eq&q[c][1][v][0][value]=Investor&timeseries=true&attributes=custom_fields.co_valuations_usd,custom_fields.fmv,custom_fields.fmv_usd&button="
  end
end


Given('the Portfolio Company Report widget has metadata with show_currency_filter false') do
  # Ensure we have a report
  unless @valuation_report
    @valuation_report = Report.find_or_create_by!(
      entity: @entity,
      name: 'Valuation Report',
      curr_role: 'company_admin',
      category: 'Valuation'
    ) do |report|
      report.user = @user
      report.url = "/valuations?q[c][0][a][0][name]=owner_id&q[c][0][p]=eq&q[c][0][v][0][value]=#{@portfolio_company.id}&q[c][1][a][0][name]=owner_type&q[c][1][p]=eq&q[c][1][v][0][value]=Investor&timeseries=true&attributes=custom_fields.co_valuations_usd,custom_fields.fmv,custom_fields.fmv_usd&button="
    end
  end

  widget = DashboardWidget.find_or_initialize_by(
    entity_id: @entity.id,
    dashboard_name: 'Portfolio Company Dashboard',
    widget_name: 'Portfolio Company Report',
    name: 'Default'
  )

  widget.assign_attributes(
    enabled: true,
    position: 3,
    size: 'XL',
    tags: 'Valuations',
    metadata: "{report_id: #{@valuation_report.id}, show_currency_filter: false}"
  )
  widget.save!
end

Then('I should see a currency dropdown for valuations') do
  # Wait for the portfolio company report widget to load (it uses turbo frames)
  sleep(3)

  # The valuation time series currency dropdown
  expect(page).to have_css('select#valuation_currency_select', visible: true)
end

Then('I should not see a currency dropdown for valuations') do
  # The valuation time series currency dropdown should not be visible
  expect(page).not_to have_css('select#valuation_currency_select', visible: true)
end