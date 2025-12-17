class AiReportSection < ApplicationRecord
  belongs_to :ai_portfolio_report
  
  
  validates :section_type, presence: true

  def completed?
    content_html.present?
  end
  
  # Get all associated charts
  def agent_charts
    return [] if agent_chart_ids.blank?
    AgentChart.where(id: agent_chart_ids)
  end
  
  # Add a chart to this section
  def add_chart(chart)
    self.agent_chart_ids ||= []
    self.agent_chart_ids << chart.id unless agent_chart_ids.include?(chart.id)
    save
  end
  
  # Check if this is a charts section
  def charts_section?
    section_type == "Custom Charts"
  end

  # Determine if web search version should be displayed
  # Based on comparing timestamps - whichever was last updated is shown
  def show_web_search_version?
    return false if updated_at_web_included.blank?
    return true if updated_at_document_only.blank?

    updated_at_web_included > updated_at_document_only
  end

  # Get the appropriate content based on timestamp comparison
  def current_content
    show_web_search_version? ? content_html_with_web : content_html
  end

  # Check if web search content has ever been generated
  def web_search_content_exists?
    content_html_with_web.present?
  end
end