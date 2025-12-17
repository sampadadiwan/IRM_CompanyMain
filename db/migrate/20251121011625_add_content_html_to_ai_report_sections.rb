class AddContentHtmlToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_report_sections, :content_html, :text
  end
end
