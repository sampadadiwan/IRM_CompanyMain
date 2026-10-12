# What the gate is expected to do to the next dealing date's open redemptions, for the order book's
# Redemptions list: each request's own row carries its value, the running total in queue order, and
# what is paid on the date versus carried to the next one — so the list needs no second "queue" table.
# Uses the same GateAllocator as the confirm (FIFO or pro-rata, fund or class level, amount vs units
# rounding), priced at each class's latest approved NAV. It is an estimate: the dealing date's preview
# re-prices at that date's NAV and also applies investor-level caps. Gate already used this period is
# subtracted here too (review fix 8).
# Worked example H34 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenGateForecast
  # One queued redemption. value/paid/carried are nil when its class has no approved NAV yet.
  Row = Data.define(:order, :units, :value_cents, :running_cents, :paid_units, :paid_cents, :carried_units, :carried_cents) do
    # :full, :part, :carried, or :no_nav
    def outcome
      return :no_nav if value_cents.nil?
      return :full if carried_units.to_d.zero?

      paid_units.to_d.positive? ? :part : :carried
    end
  end

  # gate_cents is the gate LEFT on the date; gate_used_cents what earlier dates in the same gate period
  # already paid (review fix 8), nil when unknown (fills stored before the fix) or no gate
  Result = Data.define(:dealing_date, :rows, :gate_cents, :queued_cents, :carried_cents, :gate_method, :gate_used_cents) do
    def gated?
      !gate_cents.nil?
    end

    # Data is frozen, so no memoised index; the queue for one date is short
    def row_for(order)
      rows.find { |r| r.order.id == order.id }
    end
  end

  # open_redemptions: every open redemption of the fund, in queue order (they may span dealing dates)
  def self.call(fund, open_redemptions)
    new(fund, open_redemptions).call
  end

  # The dealing date page's real pricing (DealingPricer#preview) in the same shape, so both screens render
  # the same redemption rows; here the figures are what Confirm dealing will apply, not an estimate
  def self.from_pricing(pricing)
    running = 0.to_d
    rows = pricing.redemptions.map do |r|
      running += r.requested_value_cents.to_d
      Row.new(order: r.order, units: r.requested_units, value_cents: r.requested_value_cents.to_d, running_cents: running,
              paid_units: r.filled_units, paid_cents: r.value_cents.to_d, carried_units: r.carried_units,
              carried_cents: r.requested_value_cents.to_d - r.value_cents.to_d)
    end
    gate = pricing.gate
    Result.new(dealing_date: pricing.dealing_date, rows:, gate_cents: gate[:pools].values.compact.presence&.sum, queued_cents: running,
               carried_cents: rows.sum(&:carried_cents), gate_method: gate[:method], gate_used_cents: gate[:used].to_h.values.sum.presence)
  end

  # A confirmed dealing date's stored redemption fills in the same shape — what was actually paid and
  # carried, at the NAV it was priced at — so the confirmed page keeps the preview's columns
  def self.from_fills(dealing_date, fills)
    running = 0.to_d
    rows = fills.sort_by { |f| [f.dealing_order.received_at, f.dealing_order_id] }.map do |f|
      carried_cents = (f.carried_units.to_d * f.nav_per_unit_cents.to_d).round(2)
      value = f.amount_cents.to_d + carried_cents
      running += value
      Row.new(order: f.dealing_order, units: f.units.to_d + f.carried_units.to_d, value_cents: value, running_cents: running,
              paid_units: f.units, paid_cents: f.amount_cents.to_d, carried_units: f.carried_units, carried_cents:)
    end
    gate = dealing_date.gate_snapshot.to_h
    pools = gate["pools"].to_h.values.compact.map(&:to_d)
    Result.new(dealing_date:, rows:, gate_cents: pools.presence&.sum, queued_cents: running,
               carried_cents: rows.sum(&:carried_cents), gate_method: gate["method"] || dealing_date.fund.evergreen_fund_setting.gate_method,
               gate_used_cents: gate["used"].to_h.values.sum(&:to_d).presence)
  end

  def initialize(fund, open_redemptions)
    @fund = fund
    @setting = fund.evergreen_fund_setting
    @open = open_redemptions.to_a
  end

  def call
    return nil if @open.empty?

    # The gate applies per dealing date: forecast only the earliest one that still has open redemptions
    dealing_date = @open.map(&:dealing_date).min_by(&:date)
    queue = @open.select { |o| o.dealing_date_id == dealing_date.id }

    # Latest approved NAV per class — every class, since a fund-level gate is a % of the whole fund
    navs = @fund.unit_types_list.index_with { |ut| FundNav.latest_approved(@fund, ut, Time.zone.today) }
    priced, unpriced = queue.partition { |o| navs[o.unit_type] }

    # Same allocation the confirm runs; requests keep queue order
    requests = priced.map { |o| request_for(o, navs[o.unit_type]) }
    used = @setting.gate_pct.to_d.positive? ? DealingPricer.gate_used(@fund, @setting, dealing_date.date, excluding_dealing_date_id: dealing_date.id) : {}
    pools = gate_pools(navs, used)
    fills = GateAllocator.allocate(requests:, pools:, level: @setting.gate_level, method: @setting.gate_method).index_by(&:order_id)
    requests_by_id = requests.index_by(&:order_id)

    # Walk the queue in order, keeping the running total of what is being asked for
    running = 0.to_d
    rows = queue.map do |o|
      next unpriced_row(o, running) if unpriced.include?(o)

      req = requests_by_id[o.id]
      fill = fills[o.id]
      running += req.requested_value
      Row.new(order: o, units: fill.filled_units + fill.carried_units, value_cents: req.requested_value,
              running_cents: running, paid_units: fill.filled_units, paid_cents: fill.value_cents,
              carried_units: fill.carried_units, carried_cents: req.requested_value - fill.value_cents)
    end

    Result.new(dealing_date:, rows:, gate_cents: pools.values.compact.presence&.sum, queued_cents: running,
               carried_cents: rows.sum { |r| r.carried_cents.to_d }, gate_method: @setting.gate_method, gate_used_cents: used.values.sum.presence)
  end

  private

  # What is still being asked for: the order less what earlier dealing dates already filled (a part-filled
  # order carries only the rest). All-units orders count the folio's free units today.
  def request_for(order, nav)
    prior = order.dealing_fills.reject { |f| f.dealing_date_id == order.dealing_date_id }
    if order.form == "amount"
      GateAllocator::Request.new(order_id: order.id, investor_id: order.investor_id, unit_type: order.unit_type, units: nil,
                                 nav_per_unit_cents: nav.nav_per_unit_cents, amount_cents: order.amount_cents.to_d - prior.sum { |f| f.amount_cents.to_d })
    else
      free = [order.free_units, 0].max
      units = order.all_units ? free : [order.units.to_d - prior.sum { |f| f.units.to_d }, free].min
      GateAllocator::Request.new(order_id: order.id, investor_id: order.investor_id, unit_type: order.unit_type, units:,
                                 nav_per_unit_cents: nav.nav_per_unit_cents, amount_cents: nil)
    end
  end

  # Gate value LEFT per pool at the latest approved NAVs; nil = no gate (everything is paid).
  # Review fix 8: less what earlier dealing dates in the same gate period already paid (`used`, from
  # DealingPricer.gate_used) — the confirm subtracts it, so the forecast must too.
  def gate_pools(navs, used)
    return Hash.new(nil) unless @setting.gate_pct.to_d.positive?

    pct = @setting.gate_pct.to_d / 100
    if @setting.gate_level == "class"
      navs.to_h { |ut, nav| [ut, nav ? (nav.nav_cents.to_d * pct) - used.fetch(ut, 0).to_d : 0.to_d] }
    else
      { "fund" => (navs.values.compact.sum { |n| n.nav_cents.to_d } * pct) - used.fetch("fund", 0).to_d }
    end
  end

  # A class with no approved NAV can't be valued; the row stays in the queue but adds nothing
  def unpriced_row(order, running)
    Row.new(order:, units: nil, value_cents: nil, running_cents: running, paid_units: nil, paid_cents: nil,
            carried_units: nil, carried_cents: nil)
  end
end
