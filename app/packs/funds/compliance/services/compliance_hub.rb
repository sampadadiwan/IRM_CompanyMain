# ⑩ The Compliance hub's sections (R170): the order of the pills, their icons, the URL each lazy pane
# loads, and which section-bar count it shows. Used by the hub page (pill tabs) and by the section bar
# on standalone and detail pages (links back to the hub with ?tab=).
# Worked example E200 — openspec/changes/fund-compliance-monitoring/business-rules.md
module ComplianceHub
  # key, label, icon, count key (compliance_section_counts), badge colour
  SECTIONS = [
    [:home, "Home", :compliance, nil, nil],
    [:register, "Register", :register, :open, "danger"],
    [:duties, "Duties", :duty, :due, "info"],
    [:facts, "Facts to confirm", :fact, :facts, "secondary"],
    [:packs, "Packs", :pack, nil, nil],
    [:setup, "Setup", :setup, nil, nil]
  ].freeze

  KEYS = SECTIONS.map(&:first).freeze

  module_function

  def frame_id(section) = "compliance_hub_#{section}_frame"

  def pane_id(section) = "compliance-#{section}-tab"

  # ?tab=compliance-register-tab → :register (unknown or blank → :home)
  def section_for(tab_param)
    KEYS.find { |k| pane_id(k) == tab_param.to_s } || :home
  end
end
