# The one rule for "which portfolio holdings may this LP see" (design card ③). Every LP surface asks it: the
# PortfolioInvestment / AggregatePortfolioInvestment policy scopes, the holdings list and its totals, the LP
# company page and the LP assistant.
#
# - A fund whose LP portfolio view is Whole fund shows all its holdings (nil = no id filter) — H1.
# - A fund on an Allocated view shows only the holdings where one of the viewer's folios has a non-zero entry
#   under the allocation formula of the fund the folio sits in — H2. Hidden funds are already excluded by the
#   scopes' show_portfolios check — E9.
#
# Built once per viewer per request (LpPortfolioVisibilityCache), so one membership query serves the request.
# Worked examples H1, H2, H15, E9–E28a, X17 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpPortfolioVisibility
  # A logged-in LP: their folios are the commitments they can see; their funds are those with an access right,
  # plus master funds reached through a feeder (FeederMasterFundAccess, the existing bridge)
  def self.for_user(user)
    LpPortfolioVisibilityCache.by_user ||= {}
    LpPortfolioVisibilityCache.by_user[user.id] ||=
      new(commitments: CapitalCommitment.for_investor(user), fund_ids: FeederMasterFundAccess.eligible_ids_for_investor(user))
  end

  # A chosen LP investor record, for the fund team's Preview as LP (not memoised)
  def self.for_investor(investor)
    commitments = investor.capital_commitments
    fund_ids = commitments.distinct.pluck(:fund_id)
    fund_ids += Fund.where(id: fund_ids).where.not(master_fund_id: nil).distinct.pluck(:master_fund_id)
    new(commitments:, fund_ids:)
  end

  def initialize(commitments:, fund_ids:)
    # [id, fund_id, folio_id] per folio — a handful of rows per LP
    @commitments = commitments.distinct.pluck(:id, :fund_id, :folio_id)
    @funds = Fund.where(id: fund_ids.uniq).index_by(&:id)
  end

  # Funds the viewer may see holdings of at all (the scopes' existing access rule)
  def fund_ids
    @funds.keys
  end

  # Funds whose holdings are narrowed to the viewer's folio (either Allocated view)
  def allocated_fund_ids
    @allocated_fund_ids ||= @funds.values.select(&:lp_folio_portfolio?).map(&:id)
  end

  # Visible aggregated holdings of a fund: nil when the fund is not narrowed (Whole fund — H1)
  def visible_api_ids(fund)
    return unless allocated_fund_ids.include?(fund.id)

    visible_apis_by_fund.fetch(fund.id, [])
  end

  # Every visible aggregated holding across the viewer's Allocated funds (for the scopes)
  def all_visible_api_ids
    visible_apis_by_fund.values.flatten
  end

  # A holding is visible as a whole: all purchases of a visible aggregated holding are visible
  def all_visible_pi_ids
    @all_visible_pi_ids ||= PortfolioInvestment.where(aggregate_portfolio_investment_id: all_visible_api_ids).pluck(:id)
  end

  def visible_company_ids(fund)
    ids = visible_api_ids(fund)
    scope = AggregatePortfolioInvestment.where(fund_id: fund.id)
    scope = scope.where(id: ids) if ids
    scope.distinct.pluck(:portfolio_company_id)
  end

  # Narrows an LP's PortfolioInvestment / AggregatePortfolioInvestment scope: whole-fund funds keep every row,
  # Allocated funds keep only visible holdings. One SQL condition (a plain string, which also avoids
  # ActiveRecord's structurally-compatible-joins rule for #or). H1 whole fund unchanged, H2 allocated narrows, X17.
  def restrict(scope)
    table = scope.table_name
    visible_ids = table == PortfolioInvestment.table_name ? all_visible_pi_ids : all_visible_api_ids
    whole_fund_ids = fund_ids - allocated_fund_ids
    scope.where("#{table}.fund_id IN (:whole) OR #{table}.id IN (:visible)",
                whole: whole_fund_ids.presence || [0], visible: visible_ids.presence || [0])
  end

  # Funds through which this company's page may be opened: the viewer can see the fund, its view is not Hidden,
  # and the company has a visible holding in it. Ordered by name — the fund selector's default is the first (H14,
  # E59). Worked examples X9–X12 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  def qualifying_funds_for(company)
    @funds.values.select { |fund| fund.entity_id == company.entity_id && fund.lp_portfolio_view != :hidden }
          .select { |fund| visible_company_ids(fund).include?(company.id) }
          .sort_by(&:name)
  end

  # May the viewer open this company's page for this fund? (the company switch is checked separately, so a
  # switched-off company says "not shared yet" rather than "no access" — E53)
  def openable?(company, fund)
    qualifying_funds_for(company).include?(fund)
  end

  # The company's visible holdings in a fund, for the holdings card (E58)
  def visible_holdings(company, fund)
    ids = visible_api_ids(fund)
    holdings = AggregatePortfolioInvestment.where(fund_id: fund.id, portfolio_company_id: company.id).includes(:investment_instrument)
    ids ? holdings.where(id: ids) : holdings
  end

  # Is this aggregated holding visible? (policy show? — X17)
  def api_visible?(api)
    ids = visible_api_ids(api.fund)
    ids.nil? || ids.include?(api.id)
  end

  def pi_visible?(portfolio_investment)
    ids = visible_api_ids(portfolio_investment.fund)
    ids.nil? || ids.include?(portfolio_investment.aggregate_portfolio_investment_id)
  end

  # The viewer's folios relevant to a fund: in the fund itself, or in its feeders (banner — H2, E23)
  def folio_labels(fund)
    relevant_commitments(fund).map(&:last).sort
  end

  # Holdings the LP assistant may read for one fund manager: every holding of Whole-fund funds, the visible ones
  # of Allocated funds, none of Hidden funds (H19, E69–E71). Feeds RunQueryTool's {VISIBLE_API_IDS}.
  def assistant_api_ids(entity_id)
    @funds.values.select { |fund| fund.entity_id == entity_id && fund.lp_portfolio_view != :hidden }.flat_map do |fund|
      visible_api_ids(fund) || AggregatePortfolioInvestment.where(fund_id: fund.id).pluck(:id)
    end
  end

  # The purchases under those holdings ({VISIBLE_PI_IDS})
  def assistant_pi_ids(entity_id)
    PortfolioInvestment.where(aggregate_portfolio_investment_id: assistant_api_ids(entity_id)).pluck(:id)
  end

  # The LP's own cost and FMV per visible holding of a fund, read from their folio entries — never recomputed
  # (H3). Only folios whose own fund is ready for own share count (a feeder folio uses the feeder's picks and
  # currency — E36). nil when no folio qualifies, so no Your columns are shown (E40).
  # Returns { api_id => { cost: Money|nil, fmv: Money|nil } }.
  def own_share(fund)
    @own_share ||= {}
    return @own_share[fund.id] if @own_share.key?(fund.id)

    @own_share[fund.id] = compute_own_share(fund)
  end

  # The fund whose formulas give this fund's own share (the fund itself, or the LP's feeder) — for the note
  def own_share_fund(fund)
    own_share_commitments(fund).first&.then { |_id, fund_id, _folio| folio_fund(fund_id) }
  end

  private

  def compute_own_share(fund)
    commitments = own_share_commitments(fund)
    return if commitments.empty?

    share_fund = folio_fund(commitments.first.second)
    formulas = { share_fund.lp_allocation_fund_formula_id => :cost, share_fund.lp_fmv_fund_formula_id => :fmv }
    pairs = commitments.flat_map { |id, _fund_id, _folio| formulas.keys.map { |formula_id| [id, formula_id] } }
    rows = LpFolioAllocationQuery.latest_amounts(pairs)
    api_of_pi = PortfolioInvestment.where(id: rows.filter_map { |type, id, _f, _a| id if type == "PortfolioInvestment" })
                                   .pluck(:id, :aggregate_portfolio_investment_id).to_h
    visible = visible_api_ids(fund)

    # E32 purchases summed to their holding; E35 several folios added; E39 a zero entry is a figure, not missing
    rows.each_with_object({}) do |(type, id, formula_id, amount), share|
      api_id = type == "PortfolioInvestment" ? api_of_pi[id] : id
      next if api_id.nil? || visible&.exclude?(api_id)

      key = formulas[formula_id]
      share[api_id] ||= { cost: nil, fmv: nil }
      share[api_id][key] = (share[api_id][key] || Money.new(0, share_fund.currency)) + Money.new(amount, share_fund.currency)
    end
  end

  # The viewer's folios for a fund whose own fund (or feeder) is ready for own share
  def own_share_commitments(fund)
    relevant_commitments(fund).select { |_id, fund_id, _folio| folio_fund(fund_id)&.lp_own_share_ready? }
  end

  # Allocated fund id -> visible API ids. One membership query for all the viewer's Allocated funds.
  def visible_apis_by_fund
    @visible_apis_by_fund ||= begin
      # parent_type -> ids of the subjects with a non-zero allocation-formula entry
      subjects = LpFolioAllocationQuery.membership(membership_pairs).group_by(&:first).transform_values { |rows| rows.map(&:last) }
      api_ids = subjects.fetch("AggregatePortfolioInvestment", [])
      pi_ids = subjects.fetch("PortfolioInvestment", [])
      # E21 aggregated-holding entries map directly; purchase entries map to their aggregated holding
      api_ids += PortfolioInvestment.where(id: pi_ids).distinct.pluck(:aggregate_portfolio_investment_id) if pi_ids.any?
      AggregatePortfolioInvestment.where(id: api_ids.uniq, fund_id: allocated_fund_ids)
                                  .pluck(:fund_id, :id)
                                  .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end
  end

  # (commitment, formula) pairs for commitments that can reveal holdings of an Allocated fund: folios in the
  # fund itself, or in its feeders (H15). Each uses its own fund's allocation formula; no formula, no pair (E28a).
  def membership_pairs
    allocated_fund_ids.flat_map { |fund_id| relevant_commitments(@funds[fund_id]) }.uniq.filter_map do |id, folio_fund_id, _folio|
      # The live formula, not the stored id: FundFormula is soft-deleted, and a deleted pick hides the fund's
      # holdings until the fund team picks again (E6a)
      formula_id = folio_fund(folio_fund_id)&.lp_allocation_fund_formula&.id
      [id, formula_id] if formula_id
    end
  end

  def relevant_commitments(fund)
    fund_ids = [fund.id] + feeder_ids_of(fund)
    @commitments.select { |_id, fund_id, _folio| fund_ids.include?(fund_id) }
  end

  def feeder_ids_of(fund)
    @feeder_ids ||= {}
    @feeder_ids[fund.id] ||= @commitments.map(&:second).uniq.select { |id| folio_fund(id)&.master_fund_id == fund.id }
  end

  # The fund a folio sits in — usually already loaded among the viewer's funds; kept in its own cache so a
  # feeder looked up here never widens the viewer's eligible funds
  def folio_fund(fund_id)
    @folio_funds ||= {}
    @folio_funds[fund_id] ||= @funds[fund_id] || Fund.find_by(id: fund_id)
  end
end
