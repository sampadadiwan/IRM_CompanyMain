# Presents an LP's own share for one fund: fills the Your Cost / Your FMV / Your Multiple columns on the holdings
# (the existing RansackTable reads them like any attribute) and works out the totals note. Shared by the LP
# holdings grid and the LP company page's holdings card.
# Worked examples H3, E5, E6, E32–E41 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpOwnShareSummary
  MISSING_TOOLTIP = "Not yet allocated to your folio".freeze

  # The Your columns added to the grid's default columns under own share
  COLUMNS = {
    "Your Cost; num-col" => "lp_your_cost; num-col",
    "Your FMV; num-col" => "lp_your_fmv; num-col",
    "Your Multiple; num-col" => "lp_your_multiple; num-col"
  }.freeze

  attr_reader :fund, :share_fund

  # The grid's columns with the Your columns placed right after the fund's FMV column (or at the end)
  def self.insert_columns(columns)
    fmv_key = columns.keys.find { |label| label.start_with?("Fmv") }
    return columns.merge(COLUMNS) unless fmv_key

    columns.each_with_object({}) do |(label, attribute), ordered|
      ordered[label] = attribute
      ordered.merge!(COLUMNS) if label == fmv_key
    end
  end

  # nil unless the viewer is an LP with a folio ready for own share in this fund (E40 — no Your columns)
  def self.for(user, fund)
    return unless fund && user&.curr_role_investor?

    from(LpPortfolioVisibility.for_user(user), fund)
  end

  # From an already-built visible set (the LP company page, including the fund team's preview)
  def self.from(visibility, fund)
    share = visibility.own_share(fund) if fund
    new(fund, visibility.own_share_fund(fund), share, visibility.visible_api_ids(fund)) if share
  end

  def initialize(fund, share_fund, share, visible_api_ids)
    @fund = fund
    @share_fund = share_fund
    @share = share
    @visible_api_ids = visible_api_ids || fund.aggregate_portfolio_investments.pluck(:id)
  end

  # Sets the transient Your attributes on each holding row
  def annotate(holdings)
    holdings.each do |api|
      figures = @share.fetch(api.id, {})
      api.lp_your_cost = figures[:cost] || missing_marker
      api.lp_your_fmv = figures[:fmv] || missing_marker
      api.lp_your_multiple = multiple(figures[:cost], figures[:fmv])
    end
    holdings
  end

  # Totals over every visible holding (not just the page shown). A holding without an entry for a figure is left
  # out of that figure's total and counted (E38).
  def total_cost
    total(:cost)
  end

  def total_fmv
    total(:fmv)
  end

  def total_multiple
    multiple(total_cost, total_fmv)
  end

  def missing_count
    @visible_api_ids.count { |id| @share.dig(id, :cost).nil? || @share.dig(id, :fmv).nil? }
  end

  # Formula names are read live, so a renamed formula shows its new name (E5)
  def cost_formula_name
    share_fund.lp_allocation_fund_formula&.name
  end

  def fmv_formula_name
    share_fund.lp_fmv_fund_formula&.name
  end

  private

  def total(key)
    amounts = @visible_api_ids.filter_map { |id| @share.dig(id, key) }
    amounts.sum(Money.new(0, share_fund.currency))
  end

  # E41 — the multiple uses the LP's own figures: FMV ÷ cost
  def multiple(cost, fmv)
    return if cost.nil? || fmv.nil? || cost.zero?

    format("%.2fx", fmv.to_d / cost.to_d)
  end

  # E38 — a dash with a tooltip, never a guessed figure
  def missing_marker
    ActionController::Base.helpers.content_tag(:span, "—", title: MISSING_TOOLTIP, data: { bs_toggle: "tooltip" })
  end
end
