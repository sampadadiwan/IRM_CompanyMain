class InvestmentInstrument < ApplicationRecord
  include Trackable.new
  include WithCustomField

  SECTORS = ENV["SECTORS"].split(",").sort
  CATEGORIES = JSON.parse(ENV.fetch("PORTFOLIO_CATEGORIES", nil))

  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor"
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :aggregate_portfolio_investment, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :portfolio_company_id }
  validates :category, length: { maximum: 15 }
  validates :sub_category, :sector, length: { maximum: 100 }

  def to_s
    name
  end
end
