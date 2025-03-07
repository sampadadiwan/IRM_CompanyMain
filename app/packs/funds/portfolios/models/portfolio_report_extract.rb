# This is the extract by the LLM of the data required to generate the report.
class PortfolioReportExtract < ApplicationRecord
  include Trackable.new

  belongs_to :entity
  belongs_to :portfolio_report
  belongs_to :portfolio_report_section, optional: true
  belongs_to :portfolio_company, class_name: 'Investor'
end
