class StockAdjustment < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :investment_instrument
  belongs_to :user

  validates :adjustment, numericality: true
  validates :category, length: { maximum: 10 }, allow_blank: true
  validates :sub_category, length: { maximum: 100 }, allow_blank: true

  after_create_commit :apply_stock_adjustment

  def apply_stock_adjustment
    StockAdjustmentJob.perform_later(id)
  end
end
