# What a fund's LPs see of its portfolio, as one four-option choice stored on Fund#features:
#
#   hidden               -> show_portfolios off (the folio / own-share bits are kept, so turning the
#                           portfolio back on — e.g. an upload "Show Portfolios = Yes" — restores the view)
#   whole_fund           -> show_portfolios on, no folio filter (today's behaviour)
#   allocated            -> + lp_folio_portfolio: only holdings allocated to the LP's folio
#   allocated_with_share -> + lp_own_share: also the LP's own cost and FMV
#
# Keeping show_portfolios as the "shown at all" bit means every existing show_portfolios? check
# (policies, uploads, step definitions) keeps working unchanged.
# Worked examples H4–H7, E1–E8, X1–X5 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpPortfolioView
  OPTIONS = %i[hidden whole_fund allocated allocated_with_share].freeze

  # Dropdown labels, in the order the fund form shows them
  LABELS = {
    hidden: "Hidden from LPs",
    whole_fund: "Whole fund portfolio",
    allocated: "Allocated to their folio",
    allocated_with_share: "Allocated, with their own share"
  }.freeze

  # Holding-level allocation formulas: the only ones that can decide visibility or give an LP's own share.
  # Proforma, company-level and non-portfolio formulas are refused (X4, X5).
  OWN_SHARE_RULE_TYPES = %w[AllocatePortfolioInvestment AllocateMasterFundPortfolioInvestment AllocateAggregatePortfolios].freeze

  ALLOCATION_FORMULA_MISSING = "Choose the allocation formula that decides which holdings LPs see.".freeze
  FMV_FORMULA_MISSING = "Choose the allocation formula that gives the LP's FMV.".freeze
  SAME_FORMULA = "Your cost and Your FMV must use different formulas.".freeze
  FOREIGN_FORMULA = "Pick one of this fund's portfolio allocation formulas.".freeze
  NO_FOLIO_ALLOCATIONS = "No folio allocations found for this fund yet. LPs will see an empty portfolio until an allocation run completes.".freeze

  # Reads the option back from the stored bits (H6, H7)
  def self.from_flags(features)
    return :hidden unless features.set?(:show_portfolios)
    return :whole_fund unless features.set?(:lp_folio_portfolio)
    return :allocated unless features.set?(:lp_own_share)

    :allocated_with_share
  end

  # Writes an option onto the fund's bits. Uses the legacy show_portfolios= writer so the choice counts as
  # explicit and new-fund defaults never override it.
  def self.apply(fund, option)
    option = option.to_s.to_sym
    raise ArgumentError, "Unknown LP portfolio view #{option.inspect}" unless OPTIONS.include?(option)

    # E3 — hidden only turns the portfolio off; the folio / own-share bits are left as they are
    fund.show_portfolios = option != :hidden
    return if option == :hidden

    # whole_fund clears both extra bits; allocated sets the folio bit; with-share sets both (H5, H4)
    set_flag(fund, :lp_folio_portfolio, %i[allocated allocated_with_share].include?(option))
    set_flag(fund, :lp_own_share, option == :allocated_with_share)
  end

  # Fund validation: picks are only checked for the two allocated views; other views keep but ignore them (E4)
  def self.validate(fund)
    view = fund.lp_portfolio_view
    return unless %i[allocated allocated_with_share].include?(view)

    # X2 — an allocated view needs the allocation formula
    fund.errors.add(:base, ALLOCATION_FORMULA_MISSING) if fund.lp_allocation_fund_formula_id.blank?
    if view == :allocated_with_share
      # X1 — own share also needs the FMV formula; X3 — and it must be a different formula
      fund.errors.add(:base, FMV_FORMULA_MISSING) if fund.lp_fmv_fund_formula_id.blank?
      fund.errors.add(:base, SAME_FORMULA) if fund.lp_fmv_fund_formula_id.present? && fund.lp_fmv_fund_formula_id == fund.lp_allocation_fund_formula_id
    end

    # X4, X5 — each pick must be one of this fund's holding-level allocation formulas
    picks = [fund.lp_allocation_fund_formula_id, (fund.lp_fmv_fund_formula_id if view == :allocated_with_share)].compact
    fund.errors.add(:base, FOREIGN_FORMULA) unless picks.all? { |id| formula_ids_for(fund).include?(id.to_i) }
  end

  # This fund's formulas that may be picked (also the picker's options)
  def self.formulas_for(fund)
    return FundFormula.none if fund.new_record?

    fund.fund_formulas.where(rule_type: OWN_SHARE_RULE_TYPES).order(:name)
  end

  def self.formula_ids_for(fund)
    formulas_for(fund).pluck(:id)
  end

  def self.set_flag(fund, name, value)
    value ? fund.features.set(name) : fund.features.unset(name)
  end
  private_class_method :set_flag
end
