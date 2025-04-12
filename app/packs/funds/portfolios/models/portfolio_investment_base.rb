class PortfolioInvestmentBase < ApplicationRecord
  self.abstract_class = true

  include WithCustomField
  include ForInvestor
  include RansackerAmounts.new(fields: %w[amount cost_of_sold fmv gain])

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :valuations, through: :portfolio_company

  belongs_to :investment_instrument

  monetize :ex_expenses_base_amount_cents, :base_amount_cents, :base_cost_cents, with_currency: ->(i) { i.investment_instrument&.currency || i.fund.currency }

  monetize :net_bought_amount_cents, :net_amount_cents, :ex_expenses_amount_cents, :amount_cents, :cost_cents, :fmv_cents, :gain_cents, :unrealized_gain_cents, :cost_of_sold_cents, :transfer_amount_cents, with_currency: ->(i) { i.fund.currency }

  scope :buys, -> { where("portfolio_investments.quantity > 0") }
  scope :allocatable_buys, lambda { |portfolio_company_id, investment_instrument_id|
    where("portfolio_company_id=? and investment_instrument_id = ? and portfolio_investments.quantity > 0 and net_quantity > 0", portfolio_company_id, investment_instrument_id).order(investment_date: :asc)
  }
  scope :sells, -> { where("portfolio_investments.quantity < 0") }
  scope :conversions, -> { where.not(conversion_date: nil) }
  # This is a very important scope, used in all as_of computations. It allows us to ignore conversions that have happened after the date, but whose investment_date is before the date
  scope :before, ->(date) { where(investment_date: ..date).where("conversion_date is NULL OR conversion_date <= ?", date) }

  STANDARD_COLUMNS = { "Portfolio Company" => "portfolio_company_name",
                       "Instrument" => "investment_instrument_name",
                       "Investment Date" => "investment_date",
                       "Amount" => "amount",
                       "Quantity" => "quantity",
                       "Cost Per Share" => "cost",
                       "FMV" => "fmv",
                       "FIFO Cost" => "cost_of_sold",
                       "Notes" => "notes" }.freeze

  def buy_sell
    buy? ? 'Buy' : 'Sell'
  end

  def to_s
    "#{portfolio_company_name} #{investment_instrument} #{buy_sell} #{investment_date}"
  end

  def folder_path
    "#{portfolio_company.folder_path}/Portfolio Investments"
  end

  def buy?
    quantity.positive?
  end

  def sell?
    quantity.negative?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount cost_of_sold created_at fmv folio_id gain investment_date net_quantity notes portfolio_company_name quantity sector sold_quantity updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund portfolio_company investment_instrument]
  end

  def name
    "#{portfolio_company_name} #{investment_instrument.name} #{investment_date}"
  end

  def cost_cents
    quantity.positive? ? (amount_cents / quantity).abs : 0
  end

  def base_cost_cents
    quantity.positive? ? (base_amount_cents / quantity).abs : 0
  end
end
