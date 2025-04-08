class AddTagsToPortfolioReportSection < ActiveRecord::Migration[7.2]
  def change
    add_column :portfolio_report_sections, :tags, :string, limit: 100
  end
end
