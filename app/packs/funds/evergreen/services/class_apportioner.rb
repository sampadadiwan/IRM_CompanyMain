# Splits fund-wide NAV lines between unit classes by each class's STAKE in the shared pool:
#   previous approved NAV + its own lines still owed then (fees payable / accrued)
#   × units now ÷ units then − its own payments since the previous NAV.
# Splitting by the previous NAV alone let an unpaid fee move value between classes (it was taken
# off twice: once in the share, once as the class's own line) — evergreen-share-classes H2, H3.
# Units, not count: classes have different NAVs per unit. A single-class fund always gets 100 %.
# Worked examples H1–H3, E1–E13 — openspec/changes/evergreen-share-classes/design.md#worked-examples
# (and open-ended-funds E7)
class ClassApportioner
  # A class's own NAV lines that are owed but not yet paid — added back to get its stake (H2, E7, E12, H5)
  OWN_LINES = %w[mgmt_fee_payable perf_fee_payable perf_fee_accrued class_expenses_payable].freeze

  # Returns { unit_type => share (BigDecimal 0..1) }.
  # paid: { unit_type => cents } — the class's own payments since its previous NAV (H3, E6, E13)
  def self.shares(inputs, unit_types, paid: {})
    # E1: one class takes everything
    return { unit_types.first => 1.to_d } if unit_types.size == 1

    stakes = unit_types.index_with { |ut| stake(inputs, ut, paid.fetch(ut, 0).to_d) }
    normalise(stakes, unit_types)
  end

  # Today's rule — units × previous NAV per unit (or the initial price). Still used to share a fee
  # over-payment, or a payment when nothing is owed, between classes (open-ended-funds E199, E200).
  def self.value_shares(inputs, unit_types)
    return { unit_types.first => 1.to_d } if unit_types.size == 1

    values = unit_types.index_with do |ut|
      price = inputs.previous_nav(ut)&.nav_per_unit_cents ||
              inputs.setting.terms_for(ut).initial_price_cents
      inputs.units_for(ut) * price.to_d
    end
    normalise(values, unit_types)
  end

  # One class's claim on the shared pool, never below zero (E3)
  def self.stake(inputs, unit_type, paid_cents)
    prev = inputs.previous_nav(unit_type)
    units_now = inputs.units_for(unit_type)
    prev_units = prev&.units_outstanding.to_d

    base = if prev && prev_units.positive?
             # Gross of what the class still owed at its previous NAV (H2, E7, E12); an uploaded NAV
             # has no fee lines, so its gross is its NAV (E5). Scaled for units issued or cancelled
             # since, at the previous gross per unit (E4).
             gross = prev.nav_cents.to_d + OWN_LINES.sum { |line| prev["#{line}_cents"].to_d }
             gross * units_now / prev_units
           else
             # E2: no previous NAV (or no units then) — units at the class's starting price
             price = prev&.nav_per_unit_cents || inputs.setting.terms_for(unit_type).initial_price_cents
             units_now * price.to_d
           end

    # H3, E6: what was paid for this class since came out of the shared cash, so it comes off its stake
    [base - paid_cents, 0].max
  end

  # Shares summing to exactly 1; E11: nothing anywhere → an equal split
  def self.normalise(values, unit_types)
    total = values.values.sum
    return unit_types.index_with { 1.to_d / unit_types.size } if total.zero?

    shares = values.transform_values { |v| (v / total).round(10) }
    # E10: rounding to 10 dp can leave the shares a hair off 1 (three equal classes sum to
    # 0.9999999999, ₹0.10 on a ₹100 Cr pool) — the largest class takes the remainder, so the
    # class NAVs add up to the pool exactly
    largest = values.max_by { |_ut, v| v }.first
    shares[largest] += 1 - shares.values.sum
    shares
  end

  private_class_method :stake, :normalise
end
