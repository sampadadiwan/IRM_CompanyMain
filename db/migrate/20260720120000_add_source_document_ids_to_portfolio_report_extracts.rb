class AddSourceDocumentIdsToPortfolioReportExtracts < ActiveRecord::Migration[8.1]
  def change
    add_column :portfolio_report_extracts, :source_document_ids, :json
  end
end
