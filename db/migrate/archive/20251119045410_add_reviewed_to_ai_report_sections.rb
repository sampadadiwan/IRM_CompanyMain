class AddReviewedToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_report_sections, :reviewed, :boolean, default: false
  end
end
