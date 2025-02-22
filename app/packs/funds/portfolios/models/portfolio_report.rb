class PortfolioReport < ApplicationRecord
  include ForInvestor
  belongs_to :entity
  has_many :portfolio_report_sections, dependent: :destroy
  accepts_nested_attributes_for :portfolio_report_sections, allow_destroy: true

  def to_s
    name
  end
end
