# Steps for features/fund/portfolio_report_fund_metrics.feature. They call the generator's fund-level context building
# directly: the context is what the Word template reads, and building a whole .docx adds nothing to what is checked here.

def report_fund(name)
  Fund.find_by!(name:, entity_id: @entity.id)
end

def report_instrument
  @report_instrument ||= FactoryBot.create(:investment_instrument, entity: @entity, portfolio_company: @portfolio_company)
end

def create_report_investment(fund_name, date, quantity, json_fields = {})
  pi = FactoryBot.build(:portfolio_investment, entity: @entity, fund: report_fund(fund_name), portfolio_company: @portfolio_company,
                                               investment_instrument: report_instrument, quantity:, investment_date: Date.parse(date),
                                               json_fields:)
  result = PortfolioInvestmentCreate.call(portfolio_investment: pi)
  raise "PortfolioInvestmentCreate failed: #{pi.errors.full_messages.join(', ')}" if result.failure?
end

Given('a buy in fund {string} dated {string} with stake {string}') do |fund_name, date, stake|
  create_report_investment(fund_name, date, 100, stake.present? ? { "stake" => stake } : {})
end

Given('a sale in fund {string} dated {string}') do |fund_name, date|
  create_report_investment(fund_name, date, -50)
end

# attributes: name=IRR;value=14.5;end_date=2026-03-31[;scenario=Bull Case], owned by the portfolio company
Given('the company has a fund ratio {string} in fund {string}') do |attributes, fund_name|
  attrs = attributes.split(";").to_h { |pair| pair.split("=", 2) }
  FactoryBot.create(:fund_ratio, entity: @entity, fund: report_fund(fund_name), owner: @portfolio_company,
                                 name: attrs["name"], value: attrs["value"].to_d, end_date: Date.parse(attrs["end_date"]),
                                 scenario: attrs["scenario"] || "Default")
end

Given('the fund {string} has its own IRR ratio of {int} on {string}') do |fund_name, value, end_date|
  fund = report_fund(fund_name)
  FactoryBot.create(:fund_ratio, entity: @entity, fund:, owner: fund, name: "IRR", value:, end_date: Date.parse(end_date))
end

When('the portfolio report fund data is built up to {string}') do |end_date|
  @report_context = {}
  PortfolioReportDocGenerator.allocate.send(:add_fund_level_data, @report_context, @portfolio_company, nil, Date.parse(end_date))
end

# "N/A" or a number
Then('the data for fund {string} should have {string} equal to {string}') do |fund_name, field, expected|
  value = @report_context.fetch(:"#{fund_name.parameterize.underscore}_data").object[field]
  expected == 'N/A' ? expect(value).to(eq('N/A')) : expect(value.to_f).to(eq(expected.to_f))
end

Then('the latest portfolio investment should have stake {string}') do |expected|
  expect(@report_context.fetch(:latest_pi).object.custom_fields.stake.to_s).to eq(expected)
end

Then('the latest portfolio investment should be dated {string}') do |expected|
  expect(@report_context.fetch(:latest_pi).object.investment_date.to_s).to eq(expected)
end

Then('the earliest portfolio investment should be dated {string}') do |expected|
  expect(@report_context.fetch(:earliest_pi).object.investment_date.to_s).to eq(expected)
end
