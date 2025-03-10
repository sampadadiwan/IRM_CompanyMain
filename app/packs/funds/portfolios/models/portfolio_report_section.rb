# This is used to set_portfolio_report
# 1. Section Name - this creates a new section in the generated report
# 2. Data - this is the data that is to be extracted from documents and notes, and displayed in the section
# 3. Tags - this is used to find all the notes and documents with the matching tags for extracting the data required
class PortfolioReportSection < ApplicationRecord
  belongs_to :portfolio_report
  validates :name, :data, presence: true

  # We stuff the documents to be used to generate this section here
  attr_accessor :documents
  # We stuff the notes to be used to generate this section here
  attr_accessor :notes

  def to_s
    name
  end
end
