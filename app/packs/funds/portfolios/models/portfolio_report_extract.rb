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

  # H12, E15: the latest extract (end date, then id) whose data is not blank, or nil. The database can drop null and ""
  # but not an empty [] or {} in a JSON column, so rows are checked in Ruby, newest first and a few at a time, until one
  # has data. Works on any relation: investor.portfolio_report_extracts.where(...).latest_with_data
  def self.latest_with_data(batch_size: 10)
    ordered = where.not(data: nil).where.not(data: "").order(end_date: :desc, id: :desc)
    offset = 0
    loop do
      batch = ordered.offset(offset).limit(batch_size).to_a
      found = batch.detect { |extract| extract.data.present? }
      return found if found || batch.size < batch_size

      offset += batch_size
    end
  end

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
