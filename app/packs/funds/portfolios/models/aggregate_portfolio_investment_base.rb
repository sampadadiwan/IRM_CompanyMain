class AggregatePortfolioInvestmentBase < ApplicationRecord
  self.abstract_class = true
  include ForInvestor
  include WithCustomField
  include WithDocQuestions
  include RansackerAmounts.new(fields: %w[sold_amount bought_amount fmv avg_cost])

  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument

  monetize :unrealized_gain_cents, :gain_cents, :bought_amount_cents, :net_bought_amount_cents, :sold_amount_cents, :transfer_amount_cents, :avg_cost_cents, :cost_of_sold_cents, :fmv_cents, :cost_of_remaining_cents, :portfolio_income_cents, with_currency: ->(i) { i.fund.currency }

  STANDARD_COLUMN_NAMES = ["Portfolio Company", "Instrument", "Net Bought Amount", "Sold Amount", "Current Quantity", "Fmv", "Avg Cost / Share", " "].freeze
  STANDARD_COLUMN_FIELDS = %w[portfolio_company_name investment_instrument bought_amount sold_amount current_quantity fmv avg_cost dt_actions].freeze

  STANDARD_COLUMNS = {
    "Portfolio Company" => "portfolio_company_name",
    "Instrument" => "investment_instrument_name",
    "Current Quantity" => "quantity",
    "Net Bought Amount" => "bought_amount",
    "Sold Amount" => "sold_amount",
    "Fmv" => "fmv",
    "Avg Cost / Share" => "avg_cost"
  }.freeze

  STANDARD_COLUMNS_WITH_FUND = { "Fund Name" => "fund_name" }.merge(STANDARD_COLUMNS).freeze

  INVESTOR_TAB_STANDARD_COLUMNS = STANDARD_COLUMNS_WITH_FUND.except("Portfolio Company").freeze
end
