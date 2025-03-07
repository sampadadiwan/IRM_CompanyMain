class PortfolioReport < ApplicationRecord
  include ForInvestor
  include WithFolder
  belongs_to :entity
  has_many :portfolio_report_sections, dependent: :destroy
  has_many :portfolio_report_extracts, dependent: :destroy
  accepts_nested_attributes_for :portfolio_report_sections, allow_destroy: true

  def to_s
    name
  end

  def folder_path
    "Portfolio Reports/Templates/#{name}"
  end
end
