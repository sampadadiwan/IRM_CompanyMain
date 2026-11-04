# Steps for features/startup/kpi_dashboard_widgets.feature (fix-portfolio-dashboard-widgets: KPI widgets).
# Worked examples: openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
# The KPI reports themselves come from 'the following Monthly KPI Reports exist with KPIs:' (kpi.rb).

Given('the KPI reports are open to the portfolio company') do
  KpiReport.where(portfolio_company_id: @portfolio_company.id).update_all(enable_portco_upload: true)
end

Given('the company dashboard has the widget {string} with metadata {string}') do |widget, metadata|
  @widget = DashboardWidget.create!(entity_id: @user.entity_id, dashboard_name: PORTCO_DASHBOARD, name: "Default", widget_name: widget,
                                    size: "XL", position: 1, tags: widget, display_name: true, enabled: true, show_menu: true,
                                    metadata: metadata.presence)
end

Given('I sign in as the portco user') do
  steps %(Given I log out)
  log_in(@portco_user)
end

When('I open the performance table') do
  visit(show_performance_kpi_reports_path(portfolio_company_id: @portfolio_company.id))
end

When('I open the performance table for {string}') do |as_of|
  visit(show_performance_kpi_reports_path(portfolio_company_id: @portfolio_company.id, as_of:))
end

# The refusal may surface as a raised Pundit error (test env) or as a refusal page; either way no report is shown
When('I request the performance table for {string} by URL') do |as_of|
  @refusal = nil
  begin
    visit(show_performance_kpi_reports_path(portfolio_company_id: @portfolio_company.id, as_of:))
  rescue Pundit::NotAuthorizedError => e
    @refusal = e
  end
end

# Picking an option in the dropdown submits its value as as_of (the form is a GET), so follow that request
When('I choose the month {string} in the dropdown') do |month|
  as_of = find("select#as_of").find("option", text: month)[:value]
  visit(show_performance_kpi_reports_path(portfolio_company_id: @portfolio_company.id, as_of:))
end

def month_options
  all("select#as_of option", visible: :all).map { |option| option.text(:all).strip }
end

Then('the month dropdown should list {string}') do |months|
  expect(page).to have_css("select#as_of")
  expect(month_options).to eq(months.split(",").map(&:strip))
end

Then('the month dropdown should have no months') do
  expect(page).to have_css("select#as_of")
  expect(month_options).to be_empty
end

Then('{string} should be the selected month') do |month|
  expect(find("select#as_of").value).to eq(find("select#as_of").find("option", text: month)[:value])
end

Then('the performance table should be shown') do
  expect(page).to have_css("table.numberTable")
end

Then('the performance table should not be shown') do
  expect(page).to have_no_css("table.numberTable")
end

Then('the page should say {string}') do |text|
  expect(page).to have_content(text)
end

Then('the page should offer the nearest months {string}') do |dates|
  dates.split(",").map(&:strip).each { |date| expect(page).to have_css("a[href*='as_of=#{date}']") }
end

Then('no report content should be shown') do
  expect(page).to have_no_css("table.numberTable")
  expect(page).to have_no_content("Revenue")
end

Then('the request should have been refused') do
  expect(@refusal.present? || page.has_no_css?("table.numberTable")).to be(true)
end

Then('the Key Kpis widget should show the card {string}') do |name|
  expect(find("#key_kpis_1")).to have_content(name)
end

Then('the Key Kpis widget should not show the card {string}') do |name|
  expect(page).to have_css("#key_kpis_1")
  expect(find("#key_kpis_1")).to have_no_content(name)
end

Then('the Kpis widget should show the KPI grid') do
  expect(page).to have_css("turbo-frame#kpi_reports_list[src*='grid_view=true']", visible: :all)
  expect(page).to have_no_css("turbo-frame#kpi_reports_budget", visible: :all)
end

Then('the Kpis widget should be in data-only view') do
  expect(page).to have_css("turbo-frame#kpi_reports_list[src*='compound=true']", visible: :all)
end

Then('the Kpis widget should hide the action buttons') do
  expect(page).to have_css("turbo-frame#kpi_reports_list[src*='no_actions=true']", visible: :all)
end

Then('the Kpis widget should show the action buttons') do
  expect(page).to have_css("turbo-frame#kpi_reports_list", visible: :all)
  expect(page).to have_no_css("turbo-frame#kpi_reports_list[src*='no_actions']", visible: :all)
end

Then('the field {string} should be ON') do |key|
  expect(find_field("metadata_#{key}").value).to eq("true")
end
