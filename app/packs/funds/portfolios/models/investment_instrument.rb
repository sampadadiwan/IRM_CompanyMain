class InvestmentInstrument < ApplicationRecord
  include Trackable.new
  include WithCustomField

  SECTORS = ENV["SECTORS"].split(",").sort
  CATEGORIES = JSON.parse(ENV.fetch("PORTFOLIO_CATEGORIES", nil))

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"

  validates :name, presence: true
  validates :name, uniqueness: { scope: :portfolio_company_id }
  validates :category, length: { maximum: 15 }
  validates :sub_category, :sector, length: { maximum: 100 }

  def to_s
    "#{name}: #{category} #{sub_category} #{sector}"
  end
end
