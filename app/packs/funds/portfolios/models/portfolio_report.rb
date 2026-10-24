class PortfolioReport < ApplicationRecord
  include ForInvestor
  include WithFolder

  belongs_to :entity
  has_many :portfolio_report_sections, dependent: :destroy

  validates :tags, length: { maximum: 100 }, allow_blank: true
  has_many :portfolio_report_extracts,  dependent: :destroy
  has_many :portfolio_report_templates, dependent: :destroy
  has_many :portfolio_report_drafts,    dependent: :destroy
  accepts_nested_attributes_for :portfolio_report_sections, allow_destroy: true, reject_if: :unused_section?

  def to_s
    name
  end

  # H16, H17: sections are optional, so the untouched section row of the form is dropped, not rejected
  def unused_section?(attrs)
    attrs["id"].blank? && attrs.values_at("name", "data", "icon", "tags").all?(&:blank?)
  end

  def folder_path
    "Portfolio Reports/Templates/#{name}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at updated_at name tags include_kpi include_portfolio_investments consolidated].sort
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
