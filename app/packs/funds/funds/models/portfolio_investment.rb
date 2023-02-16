class PortfolioInvestment < ApplicationRecord
  include WithCustomField
  include WithFolder

  belongs_to :entity
  belongs_to :fund
  belongs_to :aggregate_portfolio_investment
  belongs_to :portfolio_company, class_name: "Investor"

  validates :investment_date, :quantity, :amount_cents, :investment_type, presence: true
  monetize :amount_cents, :cost_cents, :fmv_cents, with_currency: ->(i) { i.fund.currency }

  counter_culture :aggregate_portfolio_investment, column_name: 'quantity', delta_column: 'quantity'
  counter_culture :aggregate_portfolio_investment, column_name: 'fmv_cents', delta_column: 'fmv_cents'

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.quantity.positive? ? "bought_quantity" : "sold_quantity" }, delta_column: 'quantity', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_quantity',
    ["portfolio_investments.quantity < ?", 0] => 'sold_quantity'
  }

  counter_culture :aggregate_portfolio_investment, column_name: proc { |r| r.quantity.positive? ? "bought_amount_cents" : "sold_amount_cents" }, delta_column: 'amount_cents', column_names: {
    ["portfolio_investments.quantity > ?", 0] => 'bought_amount_cents',
    ["portfolio_investments.quantity < ?", 0] => 'sold_amount_cents'
  }

  before_validation :setup_aggregate

  scope :buys, -> { where("portfolio_investments.quantity > 0") }
  scope :sells, -> { where("portfolio_investments.quantity < 0") }

  def setup_aggregate
    self.aggregate_portfolio_investment = AggregatePortfolioInvestment.find_or_initialize_by(fund_id:, portfolio_company_id:, entity:) if aggregate_portfolio_investment_id.blank?
  end

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  before_save :compute_fmv
  def compute_fmv
    last_valuation = portfolio_company.valuations.order(valuation_date: :desc).first
    self.fmv_cents = last_valuation ? quantity * last_valuation.per_share_value_cents : 0
  end

  after_commit :compute_avg_cost
  def compute_avg_cost
    aggregate_portfolio_investment.reload
    aggregate_portfolio_investment.compute_avg_cost
    aggregate_portfolio_investment.save
  end

  def cost_cents
    quantity.positive? ? (amount_cents / quantity).abs : 0
  end

  def to_s
    "#{portfolio_company_name} #{investment_type}"
  end

  def folder_path
    "#{portfolio_company.folder_path}/Portfolio Investments"
  end
end
