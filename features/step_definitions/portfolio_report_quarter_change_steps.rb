# Steps for features/fund/portfolio_report_company_quarter_activity.feature, features/startup/kpi_change_direction.feature,
# features/fund/portfolio_report_change_direction.feature and features/fund/portfolio_report_fmv_per_unit_change.feature.
# They build on the Inflexor quarter data and its helpers in portfolio_report_quarter_metrics_steps.rb.

# ── Quarter activity in the company report (features/fund/portfolio_report_company_quarter_activity.feature) ───────────────

# A purchase in a second fund, created here if it does not exist yet. H5
Given('{string} buys {int} crore of shares in the second fund {string} on {string}') do |name, crore, fund_name, date|
  company = Investor.find_by!(investor_name: name)
  instrument = InvestmentInstrument.find_by!(portfolio_company_id: company.id)
  fund = Fund.find_by(name: fund_name) || FactoryBot.create(:fund, entity: @fund.entity, name: fund_name, currency: "INR")
  pi = FactoryBot.build(:portfolio_investment, entity: fund.entity, fund:, portfolio_company: company, investment_instrument: instrument,
                                               quantity: 100, investment_date: Date.parse(date), ex_expenses_base_amount_cents: crore_cents(crore))
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?
end

# A company that bought and sold the whole holding before the period. E10
Given('Company H bought {int} crore of shares on {string} and sold them all on {string}') do |crore, buy_date, sell_date|
  company = fund_metrics_company("Company H")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: company, currency: "INR")
  fund_metrics_investment(company, instrument, buy_date, 100, crore)
  fund_metrics_investment(company, instrument, sell_date, -100, crore)
  @portfolio_companies << company
end

# The job hands the dates over as text. X1
When('the company report data is built for the text dates {string} to {string}') do |start_text, end_text|
  generator = PortfolioReportDocGenerator.allocate
  @company_report_data = @portfolio_companies.to_h do |company|
    context = {}
    generator.send(:add_fund_level_data, context, company, start_text, end_text)
    [company.investor_name, context]
  end
end

# The data of a fund other than the Inflexor one, as the template reads it (name_data)
Then('the data of {string} in the fund {string} shows {word} {string} crore') do |name, fund_name, field, expected|
  value = @company_report_data.fetch(name).fetch(:"#{fund_name.parameterize.underscore}_data").object.public_send(field)
  expect(value.cents.to_d / CRORE_CENTS).to be_within(0.05).of(expected.to_d), "#{field} was #{value.cents.to_d / CRORE_CENTS} crore"
end

# ── KPI change direction (features/startup/kpi_change_direction.feature) ──────────────────────────────────────────────

Then('the {string} KPI {string} for {string} should show in red in the grid') do |period, name, as_of|
  kpi = kpi_for_change(period, name, as_of)
  within(".value_#{kpi.id}") { expect(page).to have_css('.text-danger') }
end

# ── Budget difference and fair market value change (features/fund/portfolio_report_change_direction.feature) ──────────────

# change_percent is private and takes plain amounts, so it is called on a bare instance, as the other steps do
When('the fair market value change is worked out from {float} to {float}') do |base, current|
  @fmv_change = PortfolioReportConsolidatedDocGenerator.allocate.send(:change_percent, current, base)
end

Then('the fair market value change is {float}') do |expected|
  expect(@fmv_change).to be_a(Numeric)
  expect(@fmv_change.to_f).to be_within(0.005).of(expected)
end

Then('the fair market value change is {string}') do |expected|
  expect(@fmv_change).to eq(expected)
end

# ── Per-unit fair market value change (features/fund/portfolio_report_fmv_per_unit_change.feature) ─────────────────────────
# Small figures instead of the Inflexor crore data: units, a value per unit in rupees (stored as cents), and a cost of 1 crore
# that the fair market value does not read.

Given('a fund for the per-unit change') do
  @fund = FactoryBot.create(:fund, entity: @user.entity, name: "Unit Fund", currency: "INR")
  @portfolio_companies = []
  @unit_instruments = {}
  @unit_currency = "INR"
end

# The instruments are then valued in USD while the fund reports in INR. E29
Given('the units are valued in USD') do
  @unit_currency = "USD"
end

def unit_company(name)
  Investor.find_by(investor_name: name) || fund_metrics_company(name).tap { |company| @portfolio_companies << company }
end

# One instrument per company and label, created on first use
def unit_instrument(company, label)
  @unit_instruments[[company.id, label]] ||= FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: company,
                                                                                       currency: @unit_currency)
end

Given('{string} holds {int} units of {string} in the fund bought on {string}') do |name, units, label, date|
  company = unit_company(name)
  fund_metrics_investment(company, unit_instrument(company, label), date, units, 1)
end

# The purchase price is the value per unit until a valuation is stored, so a cost per unit is given for E30
Given('{string} holds {int} units of {string} in the fund bought on {string} at {int} rupees per unit') do |name, units, label, date, rupees|
  company = unit_company(name)
  fund_metrics_investment(company, unit_instrument(company, label), date, units, (units * rupees).to_d / 10_000_000)
end

Given('{string} buys {int} more units of {string} on {string}') do |name, units, label, date|
  company = unit_company(name)
  fund_metrics_investment(company, unit_instrument(company, label), date, units, 1)
end

Given('{string} sells {int} units of {string} on {string}') do |name, units, label, date|
  company = unit_company(name)
  fund_metrics_investment(company, unit_instrument(company, label), date, -units, 1)
end

Given('{string} values {string} at {int} rupees per unit on {string}') do |name, label, rupees, date|
  company = unit_company(name)
  fund_metrics_valuation(company, unit_instrument(company, label), date, rupees * 100)
end

Then('the line of {string} shows {word} {string} rupees') do |name, field, expected|
  value = fund_metrics_line(name).public_send(field)
  expect(value.cents.to_d / 100).to be_within(0.5).of(expected.to_d), "#{field} was #{value.cents.to_d / 100} rupees"
end
