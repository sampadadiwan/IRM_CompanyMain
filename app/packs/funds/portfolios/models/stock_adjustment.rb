class StockAdjustment < ApplicationRecord
  include ForInvestor

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :user
end
