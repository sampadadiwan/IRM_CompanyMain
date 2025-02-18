class StockConversion < ApplicationRecord
  include ForInvestor
  include Trackable.new

  belongs_to :entity
  belongs_to :from_portfolio_investment, class_name: "PortfolioInvestment"
  belongs_to :fund
  belongs_to :from_instrument, class_name: "InvestmentInstrument"
  belongs_to :to_instrument, class_name: "InvestmentInstrument"
  belongs_to :to_portfolio_investment, class_name: "PortfolioInvestment", optional: true

  delegate :to_s, to: :from_portfolio_investment

  validates :to_quantity, :from_quantity, :conversion_date, presence: true
  validate :from_quantity_and_intruments

  def from_quantity_and_intruments
    errors.add(:from_quantity, "cannot be greater than net quantity") if to_portfolio_investment.nil? && from_quantity > from_portfolio_investment.net_quantity
    errors.add(:from_instrument, "cannot be the same as to instrument") if from_instrument == to_instrument
  end

  scope :fund_id, ->(fund_id) { where(fund_id:) }
  scope :entity_id, ->(entity_id) { where(entity_id:) }
  scope :from_instrument_id, ->(from_instrument_id) { where(from_instrument_id:) }
  scope :to_instrument_id, ->(to_instrument_id) { where(to_instrument_id:) }
  scope :from_portfolio_investment_id, ->(from_portfolio_investment_id) { where(from_portfolio_investment_id:) }
  scope :to_portfolio_investment_id, ->(to_portfolio_investment_id) { where(to_portfolio_investment_id:) }

  def fix_bad_transfers
    StockConversion.find_each do |sc|
      sc.from_portfolio_investment.transfer_quantity = 0
      sc.from_portfolio_investment.save

      sc.from_portfolio_investment.transfer_quantity += sc.from_quantity
      PortfolioInvestmentUpdate.call(portfolio_investment: sc.from_portfolio_investment)
    end
  end
end
