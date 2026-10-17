# Picks which LP layout of the Portfolio Company Dashboard a shared company's LPs see, from the company's tags.
#
#   1. Candidates: the fund manager's LP layouts ("LP", "LP, FinTech"…) that have enabled widgets (E85 — an
#      empty matching layout is skipped).
#   2. Score: how many of a layout's tags the company carries, ignoring case and spaces (E82). The most matches
#      wins (E83); a tie goes to the layout name that comes first alphabetically (E84) and is reported so the
#      company page can warn (E92).
#   3. No tag-specific match: the plain "LP" layout (H11); none at all: nil — LPs see only the holdings card (E54).
#
# The result also feeds the guidance notices (company page, preview banner), so their wording never re-derives
# the rule. Worked examples H11, E54, E81–E85, E91, E92 —
# openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpLayoutResolver
  Result = Struct.new(:name, :matched_tags, :tie_with, keyword_init: true) do
    # Chosen as the plain "LP" layout because no tag-specific layout matched
    def fallback?
      matched_tags.empty?
    end
  end

  def self.for(company)
    new(company).call
  end

  def initialize(company)
    @company = company
  end

  def call
    # One query: the entity's LP layout names that have at least one enabled widget
    # (only widgets LPs can be shown count: KPI widgets need the KPI module — E97)
    names = DashboardWidget.enabled.where(dashboard_name: DashboardWidget::PORTFOLIO_COMPANY_DASHBOARD, entity_id: @company.entity_id,
                                          widget_name: DashboardWidget.lp_safe_widget_names(@company.entity))
                           .distinct.pluck(:name).select { |name| DashboardWidget.lp_layout_name?(name) }
    return if names.empty?

    company_tags = DashboardWidget.layout_tokens(@company.tag_list)
    scored = names.map { |name| [name, DashboardWidget.lp_layout_tags(name) & company_tags, DashboardWidget.lp_layout_tags(name)] }
    matching = scored.select { |_name, matched, _tags| matched.any? }

    return best_match(matching) if matching.any?

    # Fallback: the plain "LP" layout (no tags of its own)
    plain = scored.find { |_name, _matched, tags| tags.empty? }
    Result.new(name: plain.first, matched_tags: [], tie_with: []) if plain
  end

  private

  # Most matching tags, then name A→Z; the other layouts with the same score are reported as a tie
  def best_match(matching)
    top = matching.map { |_name, matched, _tags| matched.size }.max
    winners = matching.select { |_name, matched, _tags| matched.size == top }.sort_by(&:first)
    name, matched, = winners.first
    Result.new(name:, matched_tags: matched, tie_with: winners.drop(1).map(&:first))
  end
end
