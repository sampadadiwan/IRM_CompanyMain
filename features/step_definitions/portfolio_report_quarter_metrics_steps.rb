require "tmpdir"

# Shared setup and checks for the portfolio report fund metrics features
# (openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples).
#
# The "Inflexor quarter data" is the design's shared setup: one INR fund, Company A and Company B, share counts and
# prices chosen so every amount in the design comes out exactly (1 crore = 1,000,000,000 cents).

CRORE_CENTS = 1_000_000_000

def crore_cents(crore)
  (crore.to_d * CRORE_CENTS).to_i
end

def fund_metrics_company(name)
  steps %(Given there is an existing portfolio company "name=#{name};category=Portfolio Company")
  @investor
end

# One buy or sell in the fund, through the same service the screens use so a sale is attributed to its buy
def fund_metrics_investment(company, instrument, date, quantity, crore)
  pi = FactoryBot.build(:portfolio_investment, entity: @fund.entity, fund: @fund, portfolio_company: company,
                                               investment_instrument: instrument, quantity:, investment_date: Date.parse(date),
                                               ex_expenses_base_amount_cents: crore_cents(crore))
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?

  pi
end

def fund_metrics_valuation(company, instrument, date, price_cents)
  FactoryBot.create(:valuation, entity: @fund.entity, owner: company, investment_instrument: instrument,
                                valuation_date: Date.parse(date), per_share_value_cents: price_cents)
end

# Company A: 4,000 shares for 40 Cr (10 Feb), 500 for 10 Cr (15 Aug), 500 sold for 7 Cr on 10 Sep at a cost of 5 Cr.
# Company B: 1,000 shares for 30 Cr (20 Jan). Values per company: 31 Mar, 30 Jun, 30 Sep.
Given('the Inflexor quarter data') do
  entity = @user.entity
  @fund = FactoryBot.create(:fund, entity:, name: "Inflexor Technology Discovery Fund 1", currency: "INR")
  @company_a = fund_metrics_company("Company A")
  @company_b = fund_metrics_company("Company B")
  @portfolio_companies = [@company_a, @company_b]
  instrument_a = FactoryBot.create(:investment_instrument, entity:, portfolio_company: @company_a, currency: "INR")
  instrument_b = FactoryBot.create(:investment_instrument, entity:, portfolio_company: @company_b, currency: "INR")

  fund_metrics_investment(@company_a, instrument_a, "2026-02-10", 4000, 40)
  fund_metrics_investment(@company_b, instrument_b, "2026-01-20", 1000, 30)
  fund_metrics_investment(@company_a, instrument_a, "2026-08-15", 500, 10)
  fund_metrics_investment(@company_a, instrument_a, "2026-09-10", -500, 7)

  { "2026-03-31" => 11_250_000, "2026-06-30" => 12_500_000, "2026-09-30" => 15_000_000 }.each do |date, cents|
    fund_metrics_valuation(@company_a, instrument_a, date, cents)
  end
  { "2026-03-31" => 28_000_000, "2026-06-30" => 24_000_000, "2026-09-30" => 21_000_000 }.each do |date, cents|
    fund_metrics_valuation(@company_b, instrument_b, date, cents)
  end
end

def fund_metrics_scope(company, date)
  PortfolioInvestment.where(portfolio_company_id: company.id, fund_id: @fund.id, investment_date: ..Date.parse(date))
end

# X1 — the same investments valued for one date after another
When('the investments of {string} in the fund are valued as of {string}, then {string}, then {string}') do |name, first, second, third|
  company = Investor.find_by!(investor_name: name)
  @fmv_crore_by_date = [first, second, third].to_h do |date|
    records = PortfolioInvestmentsAsOf.call(fund_metrics_scope(company, date), Date.parse(date))
    [date, records.sum(&:fmv_cents).to_d / CRORE_CENTS]
  end
end

Then('the values are {string}, {string} and {string} crore') do |first, second, third|
  expect(@fmv_crore_by_date.values.map { |value| value.round(1) }).to eq([first, second, third].map(&:to_d))
end

# X2 — the dates the job hands over are text
Given('the consolidated generator is given the dates {string} and {string} as text') do |start_text, end_text|
  @generator = PortfolioReportConsolidatedDocGenerator.new(@portfolio_companies || [], nil, start_text, end_text, @user.id,
                                                           output_dir: Dir.tmpdir)
end

Then('the day before its start date is {string}') do |expected|
  expect(@generator.send(:prior_day)).to eq(Date.parse(expected))
end

# X3 — records that are already loaded can only be valued once
When('already loaded investments are handed to the holdings helper') do
  scope = PortfolioInvestment.where(fund_id: @fund.id)
  scope.load
  @holdings_error = begin
    PortfolioInvestmentsAsOf.call(scope, Date.new(2026, 9, 30))
    nil
  rescue ArgumentError => e
    e
  end
end

Then('the helper refuses them with an error that says they are already loaded') do
  expect(@holdings_error).to be_a(ArgumentError)
  expect(@holdings_error.message).to include("not loaded yet")
end

# ── Consolidated company fund lines (features/fund/portfolio_report_company_fund_lines.feature) ─────────────────────────

Given('the fund has commitments and collections, some of them dated after 30 September 2026') do
  build_fund_money_fixture(AS_OF_AFTER_DATES, fund: @fund)
end

# A company that held shares from before the financial year, valued at the end of December 2025 and of March 2026
Given('Company C held shares since 2025, worth {int} crore at 31 December 2025 and {int} crore at 31 March 2026') do |december, march|
  @company_c = fund_metrics_company("Company C")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: @company_c, currency: "INR")
  fund_metrics_investment(@company_c, instrument, "2025-06-01", 100, 10)
  fund_metrics_valuation(@company_c, instrument, "2025-12-31", december * CRORE_CENTS / 100)
  fund_metrics_valuation(@company_c, instrument, "2026-03-31", march * CRORE_CENTS / 100)
  @portfolio_companies << @company_c
end

Given('the fund starts its financial year in January') do
  @fund.update_columns(json_fields: (@fund.json_fields || {}).merge("month_offset_for_fy" => "0"))
end

Given('the entity starts its financial year in January and the fund has no setting of its own') do
  setting = EntitySetting.find_by(entity_id: @fund.entity_id) || EntitySetting.create!(entity: @fund.entity)
  setting.update!(month_offset_for_fy: 0)
end

Given('{string} buys {int} crore of shares on {string}') do |name, crore, date|
  company = Investor.find_by!(investor_name: name)
  instrument = InvestmentInstrument.find_by!(portfolio_company_id: company.id)
  fund_metrics_investment(company, instrument, date, 100, crore)
end

# A company whose first purchase is in the quarter, so nothing before it and no valuation
Given('Company D first buys {int} crore of shares on {string}') do |crore, date|
  @company_d = fund_metrics_company("Company D")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: @company_d, currency: "INR")
  fund_metrics_investment(@company_d, instrument, date, 100, crore)
  @portfolio_companies << @company_d
end

# Worth 10 crore at 30 June (1,000 shares at 100,000 rupees), then 1,000 more bought in August at the same price
Given('Company E is worth 10 crore at 30 June and buys 10 crore more at the same price in August') do
  @company_e = fund_metrics_company("Company E")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: @company_e, currency: "INR")
  fund_metrics_investment(@company_e, instrument, "2026-03-01", 1000, 10)
  fund_metrics_investment(@company_e, instrument, "2026-08-01", 1000, 10)
  %w[2026-03-31 2026-06-30 2026-09-30].each { |date| fund_metrics_valuation(@company_e, instrument, date, 10_000_000) }
  @portfolio_companies << @company_e
end

When('the consolidated report data is built for {string} to {string}') do |start_date, end_date|
  @generator = PortfolioReportConsolidatedDocGenerator.new(@portfolio_companies, nil, start_date, end_date, @user.id,
                                                           output_dir: Dir.tmpdir)
  companies = @portfolio_companies.sort_by { |company| company.investor_name.to_s.downcase }
  @company_hashes = companies.map { |company| @generator.send(:company_data, company) }
  @fund_totals = @generator.send(:fund_totals, @company_hashes)
end

def fund_metrics_line(name)
  hash = @company_hashes.find { |candidate| candidate[:portfolio_company].investor_name == name }
  raise "no data for #{name}" unless hash

  hash[:funds].first.object
end

Then('the line of {string} shows {word} {string} crore') do |name, field, expected|
  value = fund_metrics_line(name).public_send(field)
  expect(value.cents.to_d / CRORE_CENTS).to be_within(0.05).of(expected.to_d), "#{field} was #{value.cents.to_d / CRORE_CENTS} crore"
end

Then('the line of {string} shows {word} {string}') do |name, field, expected|
  value = fund_metrics_line(name).public_send(field)
  if expected == "N/A"
    expect(value).to eq("N/A")
  else
    expect(value.to_d).to be_within(0.05).of(expected.to_d)
  end
end

Then('the roll-forward of {string} adds up') do |name|
  line = fund_metrics_line(name)
  expect(line.cost_of_remaining_prior.cents + line.cost_of_investment_between.cents - line.cost_of_sold_between.cents)
    .to eq(line.cost_of_remaining.cents)
end

# ── Fund totals (features/fund/portfolio_report_fund_totals.feature) ──────────────────────────────────────────────

INFLEXOR_FUND = "Inflexor Technology Discovery Fund 1".freeze

Given('the fund has a {string} ratio of {float} on {string}') do |name, value, date|
  FactoryBot.create(:fund_ratio, entity: @fund.entity, fund: @fund, owner: @fund, name:, value:, end_date: Date.parse(date))
end

Given('the fund has a {string} ratio of {float} on {string} in the scenario {string}') do |name, value, date, scenario|
  FactoryBot.create(:fund_ratio, entity: @fund.entity, fund: @fund, owner: @fund, name:, value:, end_date: Date.parse(date), scenario:)
end

Given('Company F is selected but has no investment') do
  @portfolio_companies << fund_metrics_company("Company F")
end

# Its only investment in the fund is after the period
Given('Company G is selected and its only investment in the fund is dated {string}') do |date|
  company = fund_metrics_company("Company G")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: company, currency: "INR")
  fund_metrics_investment(company, instrument, date, 100, 4)
  @portfolio_companies << company
end

# A second fund that only Company D invests in, with no valuation before the period
Given('a second fund {string} that only Company D invests in, buying {int} crore on {string}') do |fund_name, crore, date|
  fund = FactoryBot.create(:fund, entity: @fund.entity, name: fund_name, currency: "INR")
  company = fund_metrics_company("Company D")
  instrument = FactoryBot.create(:investment_instrument, entity: @fund.entity, portfolio_company: company, currency: "INR")
  inflexor = @fund
  @fund = fund
  fund_metrics_investment(company, instrument, date, 100, crore)
  @fund = inflexor
  @portfolio_companies << company
end

def fund_total_named(fund_name)
  total = @fund_totals.find { |candidate| candidate.name == fund_name }
  raise "no total for #{fund_name}" unless total

  total.object
end

Then('the total of {string} shows {word} {string} crore') do |fund_name, field, expected|
  value = fund_total_named(fund_name).public_send(field)
  expect(value.cents.to_d / CRORE_CENTS).to be_within(0.05).of(expected.to_d), "#{field} was #{value.cents.to_d / CRORE_CENTS} crore"
end

Then('the total of {string} shows {word} {string}') do |fund_name, field, expected|
  value = fund_total_named(fund_name).public_send(field)
  if expected == "N/A"
    expect(value).to eq("N/A")
  else
    expect(value.to_d).to be_within(0.05).of(expected.to_d)
  end
end

# ── Company page fund data (features/fund/portfolio_report_company_fund_data.feature) ─────────────────────────────

Given('{string} sells {int} crore of shares on {string}') do |name, crore, date|
  company = Investor.find_by!(investor_name: name)
  instrument = InvestmentInstrument.find_by!(portfolio_company_id: company.id)
  fund_metrics_investment(company, instrument, date, -100, crore)
end

# The generator builds and uploads a document as soon as it is created, so the data step is called on a bare instance
When('the company report data is built for {string} to {string}') do |start_date, end_date|
  generator = PortfolioReportDocGenerator.allocate
  @company_report_data = @portfolio_companies.to_h do |company|
    context = {}
    generator.send(:add_fund_level_data, context, company, Date.parse(start_date), Date.parse(end_date))
    [company.investor_name, context]
  end
end

def company_fund_data(name)
  @company_report_data.fetch(name).fetch(:"#{INFLEXOR_FUND.parameterize.underscore}_data").object
end

Then('the fund data of {string} shows {word} {string} crore') do |name, field, expected|
  value = company_fund_data(name).public_send(field)
  expect(value.cents.to_d / CRORE_CENTS).to be_within(0.05).of(expected.to_d), "#{field} was #{value.cents.to_d / CRORE_CENTS} crore"
end
