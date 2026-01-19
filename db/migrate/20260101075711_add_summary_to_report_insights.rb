class AddSummaryToReportInsights < ActiveRecord::Migration[8.0]
  def change
    unless column_exists? :report_insights, :summary
      add_column :report_insights, :summary, :text
    end
  end
end
