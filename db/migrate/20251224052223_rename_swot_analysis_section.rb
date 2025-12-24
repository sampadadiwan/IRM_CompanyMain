class RenameSwotAnalysisSection < ActiveRecord::Migration[8.0]
  def up
    AiReportSection
      .where(section_type: "SWOT Analysis - Blitz")
      .update_all(section_type: "SWOT Analysis", web_search_enabled: true)
  end

  def down
    AiReportSection
      .where(section_type: "SWOT Analysis")
      .update_all(section_type: "SWOT Analysis - Blitz")
  end
end
