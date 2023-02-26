class AggregatePortfolioInvestment < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_investments, dependent: :destroy
  monetize :bought_amount_cents, :sold_amount_cents, :avg_cost_cents, :fmv_cents, :cost_cents, with_currency: ->(i) { i.fund.currency }

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  def to_s
    portfolio_company_name
  end

  before_save :compute_avg_cost
  def compute_avg_cost
    self.avg_cost_cents = bought_quantity.positive? ? bought_amount_cents / bought_quantity : 0
  end

  def cost_of_sold_cents
    avg_cost_cents * sold_quantity
  end

  def cost_of_net_cents
    avg_cost_cents * quantity
  end

  def fmv_cents_on_date(end_date); end

  def as_of(end_date)
    api = dup
    pis = portfolio_investments.where(investment_date: ..end_date, investment_type:)
    api.quantity = pis.sum(:quantity)
    api.bought_quantity = pis.buys.sum(:quantity)
    api.bought_amount_cents = pis.buys.sum(:amount_cents)
    api.sold_quantity = pis.sells.sum(:quantity)
    api.sold_amount_cents = pis.sells.sum(:amount_cents)
    api.compute_avg_cost

    # FMV is complicated, as the latest fmv is stored, so we need to recompute the fmv as of end_date
    valuation = api.portfolio_company.valuations.where(valuation_date: ..end_date, instrument_type: investment_type).order(valuation_date: :asc).last
    api.fmv_cents = valuation ? api.quantity * valuation.per_share_value_cents : 0
    api.freeze
  end
end
