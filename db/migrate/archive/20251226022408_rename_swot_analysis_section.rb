# db/migrate/XXXXXX_rename_swot_analysis_section.rb
class RenameSwotAnalysisSection < ActiveRecord::Migration[7.0]
  def up
    AiReportSection.where(section_type: "SWOT Analysis - Blitz").update_all(section_type: "SWOT Analysis")
  end

  def down
    AiReportSection.where(section_type: "SWOT Analysis").update_all(section_type: "SWOT Analysis - Blitz")
  end
end
