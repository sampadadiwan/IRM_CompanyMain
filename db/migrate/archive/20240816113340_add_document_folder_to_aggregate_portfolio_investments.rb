class AddDocumentFolderToAggregatePortfolioInvestments < ActiveRecord::Migration[7.1]
  def change
    add_reference :aggregate_portfolio_investments, :document_folder, null: true, foreign_key: {to_table: :folders} unless column_exists?(:aggregate_portfolio_investments, :document_folder_id)
  end
end
