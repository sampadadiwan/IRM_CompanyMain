class StockAdjustment < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :user

  after_create_commit :apply_stock_adjustment

  def investment_type
    "#{category} : #{sub_category}"
  end

  def apply_stock_adjustment
    StockAdjustmentJob.perform_later(id)
  end
end
