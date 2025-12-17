class AddWebSearchContentAndTimestampsToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    # Add column for web search content
    add_column :ai_report_sections, :content_html_with_web, :text

    # Add timestamp columns for tracking document-only content
    add_column :ai_report_sections, :created_at_document_only, :datetime
    add_column :ai_report_sections, :updated_at_document_only, :datetime

    # Add timestamp columns for tracking web search content
    add_column :ai_report_sections, :created_at_web_included, :datetime
    add_column :ai_report_sections, :updated_at_web_included, :datetime

    # Remove show_web_search as it will be derived from timestamps
    remove_column :ai_report_sections, :show_web_search, :boolean, default: false
  end
end
