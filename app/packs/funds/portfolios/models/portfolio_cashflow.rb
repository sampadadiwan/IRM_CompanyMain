class PortfolioCashflow < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :aggregate_portfolio_investment
  belongs_to :investment_instrument

  validates :payment_date, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tag, length: { maximum: 100 }

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }

  # The Portfolio Income list's columns, as plain attributes the report builder can use
  # (openspec/changes/grid-columns-inline-settings — D21)
  STANDARD_COLUMNS = {
    "Payment Date; date-col" => "payment_date; date-col",
    "Amount; num-col" => "amount; num-col",
    "Tag; text-col" => "tag; text-col",
    "Notes; text-col" => "notes; text-col"
  }.freeze
  # What the hand-built list showed, unstyled headings as before: the instrument of the aggregate investment first
  LIST_COLUMNS = {
    "Instrument" => "aggregate_portfolio_investment.investment_instrument",
    "Payment Date" => "payment_date",
    "Amount" => "amount",
    "Tag" => "tag",
    "Notes" => "notes"
  }.freeze
  # On a portfolio company's page the list leads with the fund
  WITH_FUND_LIST_COLUMNS = { "Fund Name" => "fund_name_link" }.merge(LIST_COLUMNS).freeze
  # List-only cells the columns editor offers (never the report builder) — D21
  GRID_COLUMNS = {
    "Instrument; text-col" => "aggregate_portfolio_investment.investment_instrument; text-col",
    "Fund Name; text-col" => "fund_name_link; text-col"
  }.freeze
  counter_culture :aggregate_portfolio_investment,
                  column_name: proc { |r| r.tag == "Actual" ? 'portfolio_income_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["portfolio_cashflows.tag = ?", "Actual"] => 'portfolio_income_cents'
                  }

  scope :actual, -> { where(tag: "Actual") }
  scope :not_actual, -> { where.not(tag: "Actual") }

  def initialize(*)
    super
    self.tag = "Actual" if tag.blank?
  end
end
