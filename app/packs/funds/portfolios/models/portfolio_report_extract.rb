# This is the extract by the LLM of the data required to generate the report.
class PortfolioReportExtract < ApplicationRecord
  include Trackable.new

  belongs_to :entity
  belongs_to :portfolio_report
  belongs_to :portfolio_report_section, optional: true
  belongs_to :portfolio_company, class_name: 'Investor'
  has_one :tear_sheet_presentation, dependent: :destroy

  # scope :matching is used to find extracts for a given report, company, and date range. This is used to avoid generating duplicate extracts.
  scope :matching, lambda { |portfolio_report_id, portfolio_company_id, start_date, end_date|
    where(portfolio_report_id:, portfolio_company_id:, start_date:, end_date:)
  }

  # The source documents this extract was built from (the KPI report's documents).
  # Stored as ids on the extract so they can be replayed as audits in the report.
  def source_documents
    Document.where(id: source_document_ids || [])
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at updated_at portfolio_report_id portfolio_company_id start_date end_date].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[portfolio_report portfolio_company].sort
  end
end
