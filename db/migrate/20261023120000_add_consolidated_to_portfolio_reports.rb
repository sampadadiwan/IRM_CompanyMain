class AddConsolidatedToPortfolioReports < ActiveRecord::Migration[8.1]
  def change
    add_column :portfolio_reports, :consolidated, :boolean, default: false, null: false
  end
end
