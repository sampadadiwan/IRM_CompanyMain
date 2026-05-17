class AddIconToPortfolioReportSections < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:portfolio_report_sections, :icon)
      add_column :portfolio_report_sections, :icon, :string, limit: 50
    end
  end
end
