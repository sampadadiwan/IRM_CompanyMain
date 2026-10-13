# Reads everything a NAV draft needs from data CapHive already has. Aggregates only — never loads
# account_entries rows (CLAUDE.md large-table rules).
# Worked examples H3, X5, E35 — openspec/changes/open-ended-funds/design.md#worked-examples
class NavInputs
  class MissingValuation < StandardError; end

  # Entry type the "Management Fee on NAV" formula writes (card ⑧)
  MGMT_FEE_ENTRY_TYPE = "Management Fees".freeze

  attr_reader :fund, :nav_date, :setting

  def initialize(fund, nav_date)
    @fund = fund
    @nav_date = nav_date
    @setting = fund.evergreen_fund_setting
  end

  # Fair value of every holding on the date, per holding so a missing valuation names the company.
  # Worked example X5
  def investments_fmv_cents
    @investments_fmv_cents ||= fund.aggregate_portfolio_investments.includes(:portfolio_company).sum do |api|
      api.fmv_on_date(nav_date).to_d
    rescue RuntimeError => e
      raise unless e.message.start_with?("No valuation found")

      raise MissingValuation, "No valuation for #{api.portfolio_company&.investor_name} on or before #{I18n.l(nav_date, format: :day_month_year)} — add one or upload the NAV"
    end
  end

  # Latest fund-level ledger balance by name on or before the date (same rule as "Cash In Hand" in
  # FundPortfolioCalcs#cash_in_hand_cents)
  def ledger_balance_cents(name)
    fund.fund_account_entries.where(name:, reporting_date: ..nav_date)
        .order(reporting_date: :desc).pick(:amount_cents).to_d
  end

  # Names of fund-level ledger entries that look class-specific ("Class …") but that no class uses as
  # its expense entries — shown as a warning so a class expense is never silently ignored. Names only,
  # deduplicated in SQL, at most 20 (CLAUDE.md large-table rules). evergreen-share-classes E22, E23
  def unclaimed_class_entries(claimed_names)
    claimed = claimed_names.compact.map(&:downcase)
    fund.fund_account_entries.where(reporting_date: ..nav_date).where("account_entries.name LIKE ?", "Class %")
        .distinct.order(:name).limit(20 + claimed.size).pluck(:name)
        .reject { |name| claimed.include?(name.downcase) }.first(20)
  end

  # Fund-level entries by name within (from, to] — fee payments
  def ledger_sum_cents(name, from_exclusive, to)
    scope = fund.fund_account_entries.where(name:, reporting_date: ..to)
    scope = scope.where("account_entries.reporting_date > ?", from_exclusive) if from_exclusive
    scope.sum(:amount_cents).to_d
  end

  # Units outstanding per class on the date — net of units redeemed on a dealing date on or before
  # it but not yet paid (and so not yet cancelled): they belong to departing investors (E202)
  def units_by_class
    @units_by_class ||= begin
      issued = FundUnit.where(fund_id: fund.id, issue_date: ..nav_date).group(:unit_type).sum(:quantity).transform_values(&:to_d)
      unpaid_redemptions.each { |f| issued[f.unit_type] = issued.fetch(f.unit_type, 0.to_d) - f.units.to_d }
      issued
    end
  end

  # ── Dealing in progress (decision 8 Oct 2026, E201–E204) ──────────────────────────────────────
  # Money in the bank on the NAV date that is not the fund's investors' money yet:
  #   - subscriptions paid on or before the NAV date for a dealing date AFTER it (E201, E203)
  #   - the net payout of redemptions dealt on or before the NAV date but not paid by it (E202)
  # => { unit_type => { cents:, items: [[label, cents], ...] } } — each charged to its order's class
  def dealing_in_progress
    @dealing_in_progress ||= begin
      out = Hash.new { |h, k| h[k] = { cents: 0.to_d, items: [] } }
      advance_subscriptions.each do |order, cents|
        add_item(out, order.unit_type, "#{order.investor.investor_name} — subscription for #{I18n.l(order.dealing_date.date)}", cents)
      end
      unpaid_redemptions.each do |fill|
        add_item(out, fill.unit_type, "#{fill.dealing_order.investor.investor_name} — redemption dealt #{I18n.l(fill.dealing_date.date)}, unpaid",
                 fill.amount_cents.to_d - fill.early_fee_cents.to_d)
      end
      out
    end
  end

  def dealing_in_progress_cents(unit_type)
    dealing_in_progress.key?(unit_type) ? dealing_in_progress[unit_type][:cents] : 0.to_d
  end

  def dealing_in_progress_total_cents
    dealing_in_progress.values.sum { |v| v[:cents] }
  end

  def units_for(unit_type)
    units_by_class.fetch(unit_type, 0.to_d)
  end

  def class_folio_ids(unit_type)
    @class_folio_ids ||= {}
    @class_folio_ids[unit_type] ||= fund.capital_commitments.where(unit_type:).pluck(:id)
  end

  # Management-fee accruals of a class's folios within (from, to]
  def mgmt_fee_accrued_cents(unit_type, from_exclusive)
    scope = AccountEntry.where(fund_id: fund.id, entry_type: MGMT_FEE_ENTRY_TYPE, reporting_date: ..nav_date,
                               capital_commitment_id: class_folio_ids(unit_type))
    scope = scope.where("account_entries.reporting_date > ?", from_exclusive) if from_exclusive
    scope.sum(:amount_cents).to_d
  end

  # Management-fee accruals of a class's folios in (after, upto], summed per reporting date — one grouped
  # aggregate, never the rows (CLAUDE.md). The late-fee finder buckets them into NAV periods.
  # evergreen-late-management-fees H105, E330–E332
  def mgmt_fee_sums_by_date(unit_type, after, upto)
    scope = AccountEntry.where(fund_id: fund.id, entry_type: MGMT_FEE_ENTRY_TYPE, reporting_date: ..upto,
                               capital_commitment_id: class_folio_ids(unit_type))
    scope = scope.where("account_entries.reporting_date > ?", after) if after
    scope.group(:reporting_date).sum(:amount_cents).transform_values(&:to_d)
  end

  # The last date the class's management fee was accrued to (drives the E35 warning)
  def mgmt_fee_accrued_to(unit_type)
    AccountEntry.where(fund_id: fund.id, entry_type: MGMT_FEE_ENTRY_TYPE, reporting_date: ..nav_date,
                       capital_commitment_id: class_folio_ids(unit_type)).maximum(:reporting_date)
  end

  # [[order, cents received on or before the NAV date], ...] for subscriptions dealt after the NAV date
  def advance_subscriptions
    @advance_subscriptions ||= begin
      orders = DealingOrder.where(fund_id: fund.id, kind: "subscription").where.not(status: %w[cancelled rejected])
                           .where.not(capital_remittance_id: nil).joins(:dealing_date)
                           .where("dealing_dates.date > ?", nav_date).includes(:investor, :dealing_date).to_a
      paid = CapitalRemittancePayment.where(capital_remittance_id: orders.map(&:capital_remittance_id), payment_date: ..nav_date)
                                     .group(:capital_remittance_id).sum(:amount_cents)
      orders.filter_map { |o| [o, paid[o.capital_remittance_id].to_d] if paid[o.capital_remittance_id].to_d.positive? }
    end
  end

  # [date, cents] of the latest advance subscription payment, and the date of the cash balance the
  # NAV reads — the line assumes that balance already includes the money (E205)
  def latest_advance_payment
    orders = advance_subscriptions.map(&:first)
    return nil if orders.empty?

    CapitalRemittancePayment.where(capital_remittance_id: orders.map(&:capital_remittance_id), payment_date: ..nav_date)
                            .order(payment_date: :desc).pick(:payment_date)
  end

  def cash_balance_date
    fund.fund_account_entries.where(name: setting.cash_entry_name, reporting_date: ..nav_date).maximum(:reporting_date)
  end

  # Redemption fills dealt on or before the NAV date whose payment was not completed by it
  def unpaid_redemptions
    @unpaid_redemptions ||= DealingFill.where(fund_id: fund.id, kind: "redemption").where("dealing_fills.units > 0")
                                       .joins(:dealing_date).where(dealing_dates: { status: %w[confirmed closed], date: ..nav_date })
                                       .includes(:capital_distribution_payment, :dealing_date, dealing_order: :investor).to_a
                                       .reject { |f| (p = f.capital_distribution_payment) && p.completed && p.payment_date && p.payment_date <= nav_date }
  end

  # The approved NAV before this date for a class (previous payable balances, class share)
  def previous_nav(unit_type)
    FundNav.approved.where(fund_id: fund.id, unit_type:).where(nav_date: ...nav_date).order(nav_date: :desc).first
  end

  # The mark in force and the date it was set: the last crystallisation, else the first approved NAV.
  # Worked examples H29, E39
  def high_water_mark(unit_type)
    scope = FundNav.approved.where(fund_id: fund.id, unit_type:).where(nav_date: ...nav_date)
    crystallised = scope.where(crystallised: true).order(nav_date: :desc).first
    return [crystallised.hwm_after_cents, crystallised.nav_date] if crystallised

    first = scope.order(:nav_date).first
    first ? [first.nav_per_unit_cents, first.nav_date] : [nil, nil]
  end

  private

  def add_item(out, unit_type, label, cents)
    out[unit_type][:cents] += cents
    out[unit_type][:items] << [label, cents]
  end
end
