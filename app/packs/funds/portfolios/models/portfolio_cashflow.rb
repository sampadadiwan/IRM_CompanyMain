class PortfolioCashflow < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include WithFolder

  belongs_to :entity
  belongs_to :fund
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :aggregate_portfolio_investment
  belongs_to :investment_instrument

  validates :payment_date, presence: true
  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :tag, length: { maximum: 100 }

  monetize :amount_cents, with_currency: ->(i) { i.fund.currency }
  counter_culture :aggregate_portfolio_investment, column_name: 'portfolio_income_cents', delta_column: 'amount_cents'

  scope :actual, -> { where(tag: "Actual") }
  scope :not_actual, -> { where.not(tag: "Actual") }

  def initialize(*)
    super
    self.tag = "Actual" if tag.blank?
  end
end
