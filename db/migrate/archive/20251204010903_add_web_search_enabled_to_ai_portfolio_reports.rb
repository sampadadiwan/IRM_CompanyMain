class AddWebSearchEnabledToAiPortfolioReports < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_portfolio_reports, :web_search_enabled, :boolean, default: false
  end
end
