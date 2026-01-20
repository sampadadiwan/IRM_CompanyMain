class EnableWebSearchForDefaultSections < ActiveRecord::Migration[8.0]
  def up
    web_search_sections = [
    "Company Overview",
    "Key Products & Services",
    "Market Size & Target",
    "Recent Updates & Developments",
    "Founders & Shareholders",
    "Raise History, Valuations & Funding Trend",
    "SWOT Analysis - Blitz",
    "Competition Analysis",
    "Key Risks",
    "Operational Red Flags",
    "Negative News"
    ]
    
    AiReportSection.where(section_type: web_search_sections).update_all(web_search_enabled: true)
  end

  def down
    # Optionally revert if needed
    AiReportSection.update_all(web_search_enabled: false)
  end
end