class InvestmentInstrument < ApplicationRecord
  include Trackable.new
  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"

  validates :name, presence: true
  validates :category, length: { maximum: 15 }
  validates :sub_category, :sector, length: { maximum: 100 }
end
