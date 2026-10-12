# Statement figures for one evergreen folio and period (spec LP › Statement for a quarter): opening and
# closing units and NAV per unit, closing value, subscriptions and redemptions in the period, fees and
# units still queued. Available to SOA templates as evergreen.* (SoaGenerator).
# Worked example H39 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenStatement
  # The figures as a template sees them (evergreen.*): units as numbers (format_4_closing_units), amounts
  # and NAVs as Money in the fund currency (money_closing_value). evergreen-folio-soa ⑤
  Figures = Data.define(:opening_units, :closing_units, :opening_nav_per_unit, :closing_nav_per_unit, :closing_value,
                        :subscribed_units, :subscribed_amount, :redeemed_units, :redeemed_amount,
                        :management_fees, :performance_fees, :queued_units, :transactions)
  # One dealt subscription or redemption of the period, for a template's evergreen.transactions:each(t) loop
  Transaction = Data.define(:dealing_date, :kind, :units, :nav_per_unit, :amount, :early_fee)

  MONEY_KEYS = %w[opening_nav_per_unit closing_nav_per_unit closing_value subscribed_amount redeemed_amount management_fees performance_fees].freeze

  # SoaGenerator passes the job's date strings ("2026-10-01"); the portal and features pass Dates
  # (evergreen-folio-soa review: `"2026-10-01" - 1.day` raised before any evergreen SOA rendered)
  def initialize(folio, start_date, end_date)
    @folio = folio
    @fund = folio.fund
    @start_date = start_date.to_date
    @end_date = end_date.to_date
  end

  # Context for SOA templates: TemplateDecorator over Figures. A missing NAV stays nil, so its fields
  # print blank rather than ₹0 (E14). transactions: the period's dealt orders, oldest first, each with its
  # dealing date, NAV per unit and units — what the closed-ended remittance / payout loops don't carry.
  def template_context
    values = context.to_h do |k, v|
      [k.to_sym, MONEY_KEYS.include?(k) && !v.nil? ? Money.from_amount(v.to_d, @fund.currency) : v]
    end
    TemplateDecorator.decorate(Figures.new(**values, transactions:))
  end

  def transactions
    money = ->(cents) { Money.new(cents.to_d, @fund.currency) }
    rows = period_fills.includes(:dealing_date).order("dealing_dates.date", :id).map do |f|
      Transaction.new(dealing_date: f.dealing_date.date, kind: f.kind.capitalize, units: f.units.to_d,
                      nav_per_unit: money.call(f.nav_per_unit_cents), amount: money.call(f.amount_cents), early_fee: money.call(f.early_fee_cents))
    end
    TemplateDecorator.decorate_collection(rows)
  end

  def context
    fills = period_fills
    opening_nav = FundNav.latest_approved(@fund, @folio.unit_type, @start_date - 1.day)
    closing_nav = FundNav.latest_approved(@fund, @folio.unit_type, @end_date)
    closing_units = units(..@end_date)
    {
      "opening_units" => units(...@start_date), "closing_units" => closing_units,
      "opening_nav_per_unit" => opening_nav&.nav_per_unit, "closing_nav_per_unit" => closing_nav&.nav_per_unit,
      "closing_value" => closing_nav && (closing_units * closing_nav.nav_per_unit_cents.to_d / 100),
      "subscribed_units" => fills.where(kind: "subscription").sum(:units).to_d,
      "subscribed_amount" => fills.where(kind: "subscription").sum(:amount_cents).to_d / 100,
      "redeemed_units" => fills.where(kind: "redemption").sum(:units).to_d,
      "redeemed_amount" => fills.where(kind: "redemption").sum(:amount_cents).to_d / 100,
      "management_fees" => fee_sum(NavInputs::MGMT_FEE_ENTRY_TYPE), "performance_fees" => fee_sum(Crystalliser::ENTRY_TYPE),
      # F7: still to redeem — less earlier fills, amount-form orders at the latest NAV per unit (as the unit register)
      "queued_units" => DealingOrder.where(capital_commitment_id: @folio.id, kind: "redemption", status: DealingOrder::OPEN_STATUSES)
                                    .includes(:dealing_fills).sum { |o| o.remaining_units.to_d }
    }
  end

  private

  # Fills of this folio dealt in the period whose units have moved (allotted / cancelled)
  def period_fills
    DealingFill.joins(:dealing_date, :dealing_order).where(dealing_orders: { capital_commitment_id: @folio.id }, dealing_dates: { date: @start_date..@end_date })
               .where.not(fund_unit_id: nil)
  end

  def units(range)
    FundUnit.where(capital_commitment_id: @folio.id, issue_date: range).sum(:quantity).to_d
  end

  def fee_sum(entry_type)
    AccountEntry.where(fund_id: @fund.id, capital_commitment_id: @folio.id, entry_type:, reporting_date: @start_date..@end_date).sum(:amount_cents).to_d / 100
  end
end
