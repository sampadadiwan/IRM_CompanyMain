class AddDocumentFolderIdToPortfolioReport < ActiveRecord::Migration[7.2]
  def change
    add_column :portfolio_report_extracts, :deleted_at, :datetime, null: true
    add_index :portfolio_report_extracts, :deleted_at
    add_reference :portfolio_reports, :document_folder, null: true, foreign_key: { to_table: :folders }
  end
end
