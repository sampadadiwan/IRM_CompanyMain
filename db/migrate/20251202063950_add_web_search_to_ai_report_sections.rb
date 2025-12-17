class AddWebSearchToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_report_sections, :web_search_enabled, :boolean, default: false, null: false
  end
end
