class AddCollatedReporttoAiPortfolioReports < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_portfolio_reports, :collated_report_html, :text, limit: 16777215
  end
end
