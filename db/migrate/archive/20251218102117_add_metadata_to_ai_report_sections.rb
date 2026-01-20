class AddMetadataToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_report_sections, :metadata, :json
  end
end
