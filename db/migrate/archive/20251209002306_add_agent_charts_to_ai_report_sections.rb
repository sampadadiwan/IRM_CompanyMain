class AddAgentChartsToAiReportSections < ActiveRecord::Migration[8.0]
  def change
    # Store multiple chart IDs as JSON array for sections with multiple charts
    add_column :ai_report_sections, :agent_chart_ids, :json
    
    #add_index :ai_report_sections, :agent_chart_ids, type: :fulltext
  end
end
