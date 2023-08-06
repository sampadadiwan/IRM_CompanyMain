class PortfolioCashflow < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :aggregate_portfolio_investment

  validates :payment_date, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }
end
