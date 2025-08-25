class ScenarioInvestment < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_scenario
  belongs_to :user
  belongs_to :portfolio_company, class_name: 'Investor'
  belongs_to :investment_instrument

  validates :transaction_date, presence: true
  validates :price_cents, presence: true, numericality: { greater_than: 0 }

  monetize :price_cents, with_currency: ->(i) { i.fund.currency }

  scope :buys, -> { where("scenario_investments.quantity > 0") }
  scope :sells, -> { where("scenario_investments.quantity < 0") }

  def to_portfolio_investment
    pi = PortfolioInvestment.new(fund_id:, portfolio_company_id:, portfolio_company_name: portfolio_company.investor_name, investment_date: transaction_date, quantity:, amount_cents:, investment_instrument_id:, created_at: transaction_date)
    pi.compute_fmv
    pi.readonly!
    pi
  end

  def amount_cents
    price_cents * -quantity
  end

  # (1..100).each do |i|
  #   fpc = FundPortfolioCalcs.new(Fund.find(4), (Date.today - i.days))
  #   fpc.xirr
  # end
end
