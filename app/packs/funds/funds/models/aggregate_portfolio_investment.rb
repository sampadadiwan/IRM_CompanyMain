class AggregatePortfolioInvestment < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_investments, dependent: :destroy
  monetize :bought_amount_cents, :sold_amount_cents, :avg_cost_cents, :fmv_cents, with_currency: ->(i) { i.fund.currency }

  before_create :update_name
  def update_name
    self.portfolio_company_name ||= portfolio_company.investor_name
  end

  def to_s
    portfolio_company_name
  end

  def compute_avg_cost
    self.avg_cost_cents = bought_quantity.positive? ? bought_amount_cents / bought_quantity : 0
  end

  def cost_of_sold_cents
    avg_cost_cents * sold_quantity
  end
end
