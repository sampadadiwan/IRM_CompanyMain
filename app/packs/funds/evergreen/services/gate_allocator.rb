# Fills redemption requests up to the gate. Pure function: everything it needs comes in as inputs.
# Works in value (paise) so a request made as an amount is filled to the exact rupee:
#   investor cap — each investor's fill is first capped at their remaining % of holding for the period
#   pool         — gate value still available this period, per gate level (fund, or each class);
#                  nil means no gate
#   FIFO         — fill in queue order until the pool is used up
#   pro-rata     — fill every request by the same fraction: min(1, pool ÷ requested value)
# Units: a request made in units is filled in units truncated to 4 decimals; one made as an amount
# gets amount ÷ NAV per unit to 8 decimals (fund_units precision), so A ₹3 Cr + B ₹2.11 Cr at
# ₹10,220 cancel exactly 5,000 units between them.
# Worked examples H19, H20, E27, E28, E29, E30 — openspec/changes/open-ended-funds/design.md#worked-examples
class GateAllocator
  # amount_cents is set only for requests made as an amount
  Request = Data.define(:order_id, :investor_id, :unit_type, :units, :nav_per_unit_cents, :amount_cents) do
    def requested_value
      amount_cents&.to_d || (units.to_d * nav_per_unit_cents.to_d).round(2)
    end
  end
  Fill = Data.define(:order_id, :filled_units, :carried_units, :value_cents)

  # requests: [Request] in queue order
  # pools: { pool_key => BigDecimal cents or nil }; pool_key is "fund" or the unit type (class level)
  # level: "fund" | "class"; method: "fifo" | "pro_rata"
  # investor_caps: { [investor_id, unit_type] => units still allowed this period } (absent = uncapped)
  def self.allocate(requests:, pools:, level:, method:, investor_caps: {})
    capped = apply_investor_caps(requests, investor_caps)
    capped.group_by { |r, _| level == "class" ? r.unit_type : "fund" }.flat_map do |key, group|
      allocate_pool(group, pools[key], method)
    end
  end

  # Trim each request's value to what its investor may still redeem this period, in queue order
  def self.apply_investor_caps(requests, caps)
    remaining = caps.transform_values(&:to_d)
    requests.map do |r|
      cap_key = [r.investor_id, r.unit_type]
      value = r.requested_value
      if remaining.key?(cap_key)
        allowed_units = [remaining[cap_key], 0].max
        value = [value, (allowed_units * r.nav_per_unit_cents.to_d).round(2)].min
        remaining[cap_key] = allowed_units - (value / r.nav_per_unit_cents.to_d)
      end
      [r, value]
    end
  end

  def self.allocate_pool(group, pool_cents, method)
    # No gate: everything the investor cap allows is filled
    return group.map { |r, value| fill(r, value) } if pool_cents.nil?

    pool = [pool_cents.to_d, 0].max
    if method == "pro_rata"
      requested = group.sum { |_, value| value }
      ratio = requested.zero? ? 0 : [pool / requested, 1].min
      group.map { |r, value| fill(r, (value * ratio).round(2)) }
    else
      group.map do |r, value|
        filled = [pool, value].min
        pool -= filled
        fill(r, filled)
      end
    end
  end

  def self.fill(request, filled_value)
    nav = request.nav_per_unit_cents.to_d
    total_units = request.amount_cents ? (request.amount_cents.to_d / nav).round(8) : request.units.to_d
    if filled_value >= request.requested_value
      units = total_units
      value = request.requested_value
    elsif request.amount_cents
      units = (filled_value / nav).round(8)
      value = filled_value
    else
      units = (filled_value / nav).floor(4)
      value = (units * nav).round(2)
    end
    Fill.new(order_id: request.order_id, filled_units: units, carried_units: total_units - units, value_cents: value)
  end
end
