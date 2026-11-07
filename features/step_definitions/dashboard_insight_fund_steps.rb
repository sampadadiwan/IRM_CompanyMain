# Steps for the fund-side insight widgets (Valuation Freshness, Winners & Losers, Sector Exposure, Remittance Ageing,
# NAV per Unit Trend, Hedge Expiries):
#   features/fund/dashboard_insight_portfolio_widgets.feature, features/fund/dashboard_insight_fund_widgets.feature,
#   features/security/dashboard_insight_fund_isolation.feature
# Worked examples §4 and §5 — openspec/changes/dashboard-insight-widgets/business-rules.md
# Reuses: 'today is', 'the fund {string} holds:', 'the {string} widget on the {string} has settings {string}',
# 'I open the {string} of fund {string}', 'I open the fund dashboard {string}', 'LP {string} has folio {string} in {string}'.

FIW_LAKH_CENTS = 10_000_000 # ₹1 L in paise

module DashboardInsightFundSteps
  def fiw_company(name, entity_id = @user.entity_id)
    Investor.find_by!(entity_id:, investor_name: name)
  end

  # The widget's container on the page: the dashboard renders each widget in a div whose id is the
  # parameterised widget name plus its position
  def fiw_widget(name)
    find(".dashboard-widget-container[id^='#{name.parameterize.underscore}_']", visible: :all)
  end

  # The open (Pending/Overdue) remittances are on a commitment of this LP, created once per scenario
  def fiw_commitment(fund)
    @fiw_commitments ||= {}
    @fiw_commitments[fund.id] ||= begin
      steps %(Given LP "Asha Family Office" has folio "ASHA-#{fund.id}" in "#{fund.name}")
      CapitalCommitment.find_by!(fund:, folio_id: "ASHA-#{fund.id}")
    end
  end
end
World(DashboardInsightFundSteps)

# ---------------------------------------------------------------------------------------------------------
# Portfolio data
# ---------------------------------------------------------------------------------------------------------

Given('the insight company {string} is in the {string} sector') do |name, sector|
  fiw_company(name).update_columns(sector: sector.presence)
end

Given('the {string} holding of {string} in {string} has an unrealised gain of {string} lakh') do |instrument, company, fund_name, lakh|
  lp_holding(lp_fund(fund_name), company, instrument).update_columns(unrealized_gain_cents: lakh.to_d * FIW_LAKH_CENTS)
end

# E30 — every holding of the fund is carried at zero
Given('the fund {string} holdings have no fair value') do |fund_name|
  lp_fund(fund_name).aggregate_portfolio_investments.update_all(fmv_cents: 0)
end

# E23 — every holding of the company in the fund has no quantity left
Given('{string} has fully exited the insight company {string}') do |fund_name, company|
  lp_fund(fund_name).aggregate_portfolio_investments.where(portfolio_company_name: company).update_all(quantity: 0)
end

# PortfolioInvestmentCreate#create_valuation values the company on each purchase date (1 Jan 2025 in
# 'the fund … holds:'). Remove those so each scenario sets the valuations it is about (H9 "Never", E20–E25).
Given('the purchase-date valuations of the insight companies are removed') do
  valuations = Valuation.where(entity_id: @user.entity_id, owner_type: "Investor")
  # Purchases point at their valuation (portfolio_investments.valuation_id FK); unlink them before deleting
  PortfolioInvestment.where(valuation_id: valuations.select(:id)).update_all(valuation_id: nil)
  valuations.delete_all
end

# A valuation owned by the company (owner_type "Investor"), on the company's first instrument
Given('the insight company {string} was valued on {string}') do |name, date|
  company = fiw_company(name)
  instrument = InvestmentInstrument.where(entity_id: company.entity_id, portfolio_company: company).order(:id).first!
  FactoryBot.create(:valuation, entity: company.entity, owner: company, investment_instrument: instrument,
                                valuation_date: Date.parse(date), valuation_cents: 100 * CRORE_CENTS)
end

# X7 — another firm values its own same-named company
Given('another firm values its own company {string} on {string}') do |name, date|
  other = FactoryBot.create(:entity, entity_type: "Investment Fund", name: "Other Capital")
  company = Investor.create!(entity: other, investor_name: name, primary_email: "#{name.parameterize}@other.example.com",
                             category: "Portfolio Company")
  instrument = InvestmentInstrument.create!(entity_id: other.id, portfolio_company: company, name: "Equity",
                                            category: "Unlisted", sub_category: "Equity", currency: "INR")
  FactoryBot.create(:valuation, entity: other, owner: company, investment_instrument: instrument,
                                valuation_date: Date.parse(date), valuation_cents: 100 * CRORE_CENTS)
end

# ---------------------------------------------------------------------------------------------------------
# Remittances — figures in ₹ lakh, pinned with update_columns as lp_fund_stats.rb does
# ---------------------------------------------------------------------------------------------------------

Given('the fund {string} has these insight remittances:') do |fund_name, table|
  fund = lp_fund(fund_name)
  commitment = fiw_commitment(fund)
  table.hashes.each do |row|
    # Upload-basis call: no remittances are generated for it, so the one below is the only one
    call = FactoryBot.create(:capital_call, fund:, entity: fund.entity, call_basis: "Upload", name: row["call"])
    call.update_columns(due_date: Date.parse(row["due_date"]))
    remittance = FactoryBot.create(:capital_remittance, fund:, entity: fund.entity, capital_call: call,
                                                        capital_commitment: commitment, investor: commitment.investor,
                                                        folio_id: commitment.folio_id,
                                                        folio_committed_amount_cents: commitment.folio_committed_amount_cents)
    remittance.update_columns(call_amount_cents: row["call_amount"].to_d * FIW_LAKH_CENTS,
                              other_fee_cents: row["other_fee"].to_d * FIW_LAKH_CENTS,
                              collected_amount_cents: row["collected"].to_d * FIW_LAKH_CENTS,
                              status: row["status"])
  end
end

# ---------------------------------------------------------------------------------------------------------
# NAVs and derivatives
# ---------------------------------------------------------------------------------------------------------

# E39 — a draft NAV (not yet approved)
Given('a draft insight NAV for class {string} on {string} with NAV per unit {string}') do |unit_type, date, per_unit|
  FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: Date.parse(date), status: "draft", source: "uploaded",
                  units_outstanding: 1000, nav_per_unit_cents: per_unit.to_d * 100, nav_cents: per_unit.to_d * 100 * 1000)
end

# E40 — one approved NAV per month end, NAV per unit rising by 1 each month
Given('class {string} has approved insight NAVs for each month end from {string} to {string}') do |unit_type, from, to|
  date = Date.parse(from).end_of_month
  per_unit = 100
  while date <= Date.parse(to)
    FundNav.create!(entity_id: @fund.entity_id, fund: @fund, unit_type:, nav_date: date, status: "approved", source: "uploaded",
                    units_outstanding: 1000, nav_per_unit_cents: per_unit * 100, nav_cents: per_unit * 100 * 1000, approved_at: Time.current)
    per_unit += 1
    date = date.next_month.end_of_month
  end
end

Given('the fund {string} has these insight derivative contracts:') do |fund_name, table|
  fund = lp_fund(fund_name)
  table.hashes.each do |row|
    # An OTC forward on a currency pair: the smallest valid contract (forward_rate, notional, counterparty)
    DerivativeContract.create!(entity_id: fund.entity_id, fund:, name: row["name"], contract_type: "forward", listed: false,
                               underlying_type: "currency_pair", underlying_name: "USD/INR", side: "long", settlement: "cash",
                               counterparty_name: "HDFC Bank", currency: "USD", forward_rate: 84,
                               notional_cents: row["notional"].to_d * 100, trade_date: Date.new(2026, 1, 1),
                               expiry_date: Date.parse(row["expiry"]), status: row["status"])
  end
end

# ---------------------------------------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------------------------------------

Then('the fund insight widget {string} should say {string}') do |widget, message|
  within(fiw_widget(widget)) { expect(page).to have_css("[data-insight-empty-state]", text: message) }
end

# X9 / X2 — the widget's container is on the page but its partial rendered nothing
Then('the fund insight widget {string} should render nothing') do |widget|
  expect(fiw_widget(widget).text.strip).to eq("")
end

# "Current 0, Due 1, Stale 1, Never 1"
Then('the Valuation Freshness counts should be {string}') do |expected|
  within(fiw_widget("Valuation Freshness")) do
    actual = %w[Current Due Stale Never].map { |status| "#{status} #{find("[data-freshness-card='#{status}'] [data-freshness-count]").text}" }
    expect(actual.join(", ")).to eq(expected)
  end
end

# Rows in order: | company | status | days |
Then('the Valuation Freshness rows should be:') do |table|
  within(fiw_widget("Valuation Freshness")) do
    actual = all("tbody tr").map { |tr| [tr["data-company"], tr["data-status"], tr.all("td")[2].text] }
    expect(actual).to eq(table.raw)
  end
end

Then('Valuation Freshness should say {string}') do |text|
  within(fiw_widget("Valuation Freshness")) { expect(page).to have_css("[data-freshness-showing]", text:) }
end

Then('Valuation Freshness should not list {string}') do |company|
  within(fiw_widget("Valuation Freshness")) { expect(page).to have_no_css("tr[data-company='#{company}']") }
end

# "Zeta Foods, Kite Robotics"
Then('the Winners & Losers {string} list should be {string}') do |list, names|
  within(fiw_widget("Winners & Losers")) do
    within("[data-winners-losers='#{list}']") { expect(all("tr[data-company]").map { |tr| tr["data-company"] }.join(", ")).to eq(names) } # rubocop:disable Rails/Pluck -- Capybara nodes, not records
  end
end

Then('the Winners & Losers {string} list should say {string}') do |list, message|
  within(fiw_widget("Winners & Losers")) do
    within("[data-winners-losers='#{list}']") { expect(page).to have_css("[data-insight-empty-state]", text: message) }
  end
end

Then('the Winners & Losers {string} list should show {string} at {string}') do |list, company, amount|
  within(fiw_widget("Winners & Losers")) do
    within("[data-winners-losers='#{list}'] tr[data-company='#{company}']") { expect(page).to have_content(amount) }
  end
end

# "Consumer 60.00 %, Fintech 30.00 %, Unassigned 10.00 %"
Then('Sector Exposure should show {string}') do |expected|
  within(fiw_widget("Sector Exposure")) do
    actual = all("tr[data-sector]").map { |tr| "#{tr['data-sector']} #{tr.find('[data-sector-percent]').text}" }
    expect(actual.join(", ")).to eq(expected)
  end
end

# Rows: | bucket | count | due |
Then('Remittance Ageing should show:') do |table|
  within(fiw_widget("Remittance Ageing")) do
    actual = all("tr[data-bucket]").map { |tr| [tr["data-bucket"], tr.find("[data-bucket-count]").text, tr.find("[data-bucket-due]").text] }
    expect(actual).to eq(table.raw)
  end
end

Then('Remittance Ageing should put {int} remittance(s) in {string}') do |count, bucket|
  within(fiw_widget("Remittance Ageing")) { expect(find("tr[data-bucket='#{bucket}'] [data-bucket-count]").text).to eq(count.to_s) }
end

# E37 — the grid the link opens (CapitalRemittanceList, policy-scoped for the signed-in user) holds the same rows
Then('the remittances list behind {string} should hold {int} remittances') do |link_text, count|
  href = within(fiw_widget("Remittance Ageing")) { find_link(link_text)[:href] }
  query = Rack::Utils.parse_nested_query(URI.parse(href).query)
  result = CapitalRemittanceList.call(@user, ActionController::Parameters.new(query))
  expect(result.capital_remittances.count).to eq(count)
  total = within(fiw_widget("Remittance Ageing")) { all("[data-bucket-count]").sum { |cell| cell.text.to_i } }
  expect(total).to eq(count)
end

# "2026-07-31=101.20,2026-08-31=102.10"
Then('NAV per Unit Trend class {string} should plot {string}') do |unit_class, points|
  within(fiw_widget("NAV per Unit Trend")) { expect(find("tr[data-nav-class='#{unit_class}']")["data-nav-points"]).to eq(points) }
end

Then('NAV per Unit Trend class {string} should plot {int} points') do |unit_class, count|
  within(fiw_widget("NAV per Unit Trend")) do
    expect(find("tr[data-nav-class='#{unit_class}']")["data-nav-points"].split(",").size).to eq(count)
  end
end

# Rows in order: | contract | days left |
Then('Hedge Expiries should list:') do |table|
  within(fiw_widget("Hedge Expiries")) do
    actual = all("tr[data-contract]").map { |tr| [tr["data-contract"], tr.find("[data-days-left]").text] }
    expect(actual).to eq(table.raw)
  end
end

When('LP {string} opens the {string} of fund {string}') do |name, dashboard_name, fund_name|
  lp_sign_in(name)
  visit(dashboard_fund_path(lp_fund(fund_name), dashboard_name:))
end
