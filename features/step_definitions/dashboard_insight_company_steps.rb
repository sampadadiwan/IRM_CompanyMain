# Steps for the company insight widgets: KPI Movers, KPI Threshold Watch, Monitoring Status, Investment Timeline,
# Ownership Trend (features/startup/dashboard_insight_company_widgets.feature), Peer KPI Comparison
# (features/fund/dashboard_insight_peer_kpi.feature) and their isolation rows
# (features/security/dashboard_insight_company_isolation.feature).
# Worked examples: openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md §2, §3, §4 (H13, E31, E32, X8)
#
# Reused steps: 'today is {string}' (evergreen_order_steps.rb), 'the company dashboard has the widget {string} with
# metadata {string}' (dashboard_widget_kpi_steps.rb), 'I open the company dashboard of {string}'
# (portfolio_stats_widget_settings_steps.rb), 'the {string} widget on the {string} has settings {string}'.

# --- Setup -----------------------------------------------------------------------------------------------------

# A portfolio company of my firm, by name, created on first use
def diw_company(name)
  @diw_companies ||= {}
  @diw_companies[name] ||= Investor.find_by(entity_id: @entity.id, investor_name: name) || begin
    steps %(Given there is an existing portfolio company "name=#{name};category=Portfolio Company")
    @investor
  end
end

# A fund of my firm, by name and currency, created on first use
def diw_fund(name, currency = "INR")
  Fund.find_by(entity_id: @entity.id, name:) || FactoryBot.create(:fund, entity: @entity, name:, currency:)
end

# The firm's instrument for a company in a currency, created on first use
def diw_instrument(company, currency)
  InvestmentInstrument.find_by(entity_id: @entity.id, portfolio_company_id: company.id, currency:) ||
    FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: company, currency:, name: "#{company.investor_name} #{currency} Equity")
end

Given('my firm reports in {string} for the insight widgets') do |currency|
  @entity.update!(currency:)
end

Given('the insight portfolio companies {string} exist') do |names|
  names.split(",").map(&:strip).each { |name| diw_company(name) }
end

# One KPI report of a company with its KPIs. Table columns: name, value, change (stored % change), rag
# (red / amber / green), lower, upper (the KPI mapping's thresholds), standard (the mapping's standard name).
Given('{string} has an {string} {string} KPI report dated {string} with:') do |company_name, tag, period, date, table|
  company = diw_company(company_name)
  report = KpiReport.find_or_create_by!(entity: @entity, portfolio_company_id: company.id, period:, as_of: Date.parse(date), tag_list: tag) do |r|
    r.user = @user
  end
  table.hashes.each do |row|
    # The KPI's mapping, holding its standard name and thresholds
    mapping = InvestorKpiMapping.where(entity_id: @entity.id, investor_id: company.id, reported_kpi_name: row["name"]).first_or_initialize
    mapping.standard_kpi_name = row["standard"].presence || row["name"]
    mapping.lower_threshold = row["lower"].presence&.to_d
    mapping.upper_threshold = row["upper"].presence&.to_d
    mapping.save!
    kpi = FactoryBot.create(:kpi, kpi_report: report, entity: @entity, portfolio_company_id: company.id, name: row["name"],
                                  value: row["value"].to_f, investor_kpi_mapping: mapping, status: :approved)
    # The stored change and RAG status, written as the percentage-change job and RAG recompute would leave them
    kpi.update_columns(percentage_change: row["change"].presence&.to_d, rag_status: row["rag"].presence)
  end
end

Given('the KPI module is switched off for me') do
  @user.permissions.unset(:enable_kpis)
  @user.save!
end

Given('the cap table module is on for me') do
  @user.permissions.set(:enable_captable)
  @user.save!
  @entity.permissions.set(:enable_captable)
  @entity.save!
end

Given('my firm has a portfolio company agent') do
  @diw_agent = FactoryBot.create(:support_agent, entity: @entity, agent_type: "PortfolioCompanyAgent", name: "Portfolio Company Agent")
end

# One agent report for a company. Table columns: area (kpi / document / valuation), severity, message.
# "latest" marks it as the agent's latest report for the company; "older" does not.
Given('the portfolio company agent has an {string} report for {string} dated {string}:') do |which, company_name, date, table|
  company = diw_company(company_name)
  issues = { "kpi_issues" => [], "document_issues" => [], "valuation_issues" => [] }
  table.hashes.each do |row|
    issues["#{row['area']}_issues"] << { "severity" => row["severity"], "type" => row["type"].presence || "missing", "message" => row["message"] }
  end
  blocked = issues.values.flatten.any? { |issue| issue["severity"] == "blocking" }
  report = FactoryBot.create(:support_agent_report, support_agent: @diw_agent, owner: company, owner_name: company.investor_name,
                                                    latest: which == "latest", json_fields: issues.merge("final_status" => blocked ? "blocked" : "ready"))
  at = Time.zone.parse("#{date} 09:00")
  report.update_columns(created_at: at, updated_at: at)
end

# X5 — another firm with its own agent and a same-named company that it has checked
Given('another firm has its own agent report for a company named {string}') do |company_name|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital")
  other_company = FactoryBot.create(:investor, entity: other, investor_entity: FactoryBot.create(:entity), investor_name: company_name,
                                               category: "Portfolio Company")
  agent = FactoryBot.create(:support_agent, entity: other, agent_type: "PortfolioCompanyAgent")
  FactoryBot.create(:support_agent_report, support_agent: agent, owner: other_company, owner_name: company_name, latest: true,
                                           json_fields: { "kpi_issues" => [{ "severity" => "blocking", "message" => "Other firm's KPI issue" }] })
end

# One buy (positive quantity) or sell (negative) in a company, through the service the screens use.
# Amount is in the fund's currency, as a plain number (e.g. 10000000 = ₹1,00,00,000).
Given('{string} {string} {int} shares of {string} for {int} on {string}') do |fund_name, verb, quantity, company_name, amount, date|
  fund = diw_fund(fund_name)
  company = diw_company(company_name)
  pi = FactoryBot.build(:portfolio_investment, entity: @entity, fund:, portfolio_company: company,
                                               investment_instrument: diw_instrument(company, fund.currency),
                                               quantity: verb == "sold" ? -quantity : quantity,
                                               investment_date: Date.parse(date), ex_expenses_base_amount_cents: amount * 100)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?

  @diw_last_investment = pi
end

Given('the fund {string} is in {string}') do |fund_name, currency|
  diw_fund(fund_name, currency)
end

# E15 — the firm-currency amount the tracking-currency job fills in for a foreign-currency transaction
Given('that transaction has a firm-currency amount of {int}') do |amount|
  @diw_last_investment.update_column(:entity_currency_amount_cents, amount * 100)
end

# Cap-table positions of a company. Table columns: date (blank allowed), group, pct (blank allowed), round.
Given('{string} has the cap-table positions:') do |company_name, table|
  company = diw_company(company_name)
  table.hashes.each do |row|
    ShareholderPosition.create!(entity: @entity, investor: company, portfolio_company: company, position_type: "Shareholder",
                                category: row["group"], position_date: row["date"].presence && Date.parse(row["date"]),
                                round_name: row["round"].presence || "Series A", investor_label: "#{row['group']} holder",
                                fully_diluted_percentage: row["pct"].presence&.to_d)
  end
end

# X6 — an employee who can see the company and one fund only
Given('the employee {string} can see {string} and the fund {string} only') do |first_name, company_name, fund_name|
  employee = FactoryBot.create(:user, entity: @entity, first_name:)
  employee.add_role(:employee)
  # Same module switches as the fund manager, but an employee's (not an admin's) view of funds and companies
  employee.update_columns(permissions: @user.read_attribute(:permissions), curr_role: "employee")
  AccessRight.create!(owner: diw_fund(fund_name), access_type: "Fund", user_id: employee.id, entity_id: @entity.id)
  AccessRight.create!(owner: diw_company(company_name), access_type: "Investor", user_id: employee.id, entity_id: @entity.id)
  @diw_employee = employee
end

Given('I sign in as that employee') do
  steps %(Given I log out)
  log_in(@diw_employee)
  @user = @diw_employee
end

# --- Actions ---------------------------------------------------------------------------------------------------

When('I open the aggregated portfolio dashboard for the insight widgets') do
  visit(investors_path(multi_portfolio_dashboard: true))
end

# --- Checks ----------------------------------------------------------------------------------------------------

# The insight widget's body on the page, found by its data-insight-widget slug ("KPI Movers" → "kpi-movers")
def diw_widget(name)
  find("[data-insight-widget='#{name.parameterize}']")
end

Then('the {string} insight widget should list the rows {string}') do |name, rows|
  expected = rows.split(",").map(&:strip)
  actual = diw_widget(name).all("[data-insight-row]").pluck("data-insight-row")
  expect(actual).to eq(expected)
end

Then('the {string} insight widget row {string} should show {string}') do |name, row, text|
  within(diw_widget(name).find("[data-insight-row='#{row}']")) { expect(page).to have_content(text) }
end

Then('the {string} insight widget should show {string}') do |name, text|
  expect(diw_widget(name)).to have_content(text)
end

Then('the {string} insight widget should not show {string}') do |name, text|
  expect(diw_widget(name)).to have_no_content(text)
end

Then('the {string} insight widget should not be on the page') do |name|
  expect(page).to have_no_css("[data-insight-widget='#{name.parameterize}']")
end

Then('the {string} insight widget report date should be {string}') do |name, date|
  expect(diw_widget(name).find("[data-insight-report-date]")).to have_content(date)
end

Then('the {string} insight widget flags for {string} should be {string}') do |name, row, flags|
  actual = diw_widget(name).find("[data-insight-row='#{row}']").all("[data-insight-flag]").map { |flag| flag.text.strip }
  expect(actual).to eq(flags.split(",").map(&:strip))
end
