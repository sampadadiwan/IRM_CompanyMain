class StockAdjustment < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument
  belongs_to :user

  validates :adjustment, numericality: { less_than: 100 }

  after_create_commit :apply_stock_adjustment

  def apply_stock_adjustment
    StockAdjustmentJob.perform_later(id)
  end
end
