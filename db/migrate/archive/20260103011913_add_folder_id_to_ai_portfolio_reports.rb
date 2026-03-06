class AddFolderIdToAiPortfolioReports < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_portfolio_reports, :folder, null: true, foreign_key: true
  end
end
