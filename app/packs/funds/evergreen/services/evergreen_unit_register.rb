# The unit register: one row per folio and class, valued at the class's latest approved NAV.
# Units come from one grouped SUM over fund_units (CLAUDE.md: aggregate in SQL).
# Worked examples H35, H37, E48 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenUnitRegister
  Row = Data.define(:folio, :unit_type, :units, :nav, :value_cents, :cost_cents, :gain_pct, :locked_units, :locked_until, :queued_units)

  # folio_ids: only these folios (e.g. one folio's page), so the rest of the register isn't computed
  def initialize(fund, investor_ids: nil, folio_ids: nil, today: Time.zone.today)
    @fund = fund
    @investor_ids = investor_ids
    @folio_ids = folio_ids
    @today = today
  end

  def rows
    units = FundUnit.where(fund_id: @fund.id, issue_date: ..@today)
    units = units.where(capital_commitment_id: @folio_ids) if @folio_ids
    units = units.group(:capital_commitment_id).sum(:quantity)
    folios = @fund.capital_commitments.includes(:investor).where(id: units.keys)
    folios = folios.where(investor_id: @investor_ids) if @investor_ids
    navs = @fund.unit_types_list.index_with { |ut| FundNav.latest_approved(@fund, ut, @today) }
    setting = @fund.evergreen_fund_setting
    folios.order(:folio_id).map do |cc|
      qty = units[cc.id].to_d
      nav = navs[cc.unit_type]
      value = nav ? (qty * nav.nav_per_unit_cents.to_d).round(2) : nil
      cost = average_cost_cents(cc)
      locked_qty, locked_until = locked(cc, setting)
      # F7: what each open redemption still asks for — less what earlier dates filled, and an amount-form
      # order converted at the class's NAV per unit (it has no units of its own)
      queued = DealingOrder.where(capital_commitment_id: cc.id, kind: "redemption", status: DealingOrder::OPEN_STATUSES).includes(:dealing_fills)
                           .sum { |o| o.remaining_units(nav_per_unit_cents: nav&.nav_per_unit_cents).to_d }
      gain = value && cost.positive? ? (((value / cost) - 1) * 100).round(1) : nil
      Row.new(folio: cc, unit_type: cc.unit_type, units: qty, nav:, value_cents: value, cost_cents: cost, gain_pct: gain,
              locked_units: locked_qty, locked_until:, queued_units: queued)
    end
  end

  # Cost at average cost: amount paid for units still held (allotments in order, redemptions at the running average)
  def average_cost_cents(folio)
    held = 0.to_d
    cost = 0.to_d
    FundUnit.where(capital_commitment_id: folio.id, issue_date: ..@today).order(:issue_date, :id).pluck(:quantity, :price_cents, :premium_cents).each do |q, price, premium|
      q = q.to_d
      if q.positive?
        cost += q * (price.to_d + premium.to_d)
        held += q
      elsif held.positive?
        cost -= cost / held * -q
        held += q
      end
    end
    cost.round(2)
  end

  def locked(folio, setting)
    term = setting.terms_for(folio.unit_type)
    return [0.to_d, nil] unless term.lock_up?

    lots = EvergreenLots.remaining(folio.id, folio.unit_type)
    locked_lots = lots.select { |issued, _| issued.advance(months: term.lock_up_months) > @today }
    [locked_lots.sum { |_, q| q.to_d }, locked_lots.map { |issued, _| issued.advance(months: term.lock_up_months) }.max]
  end
end
