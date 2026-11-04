# The purchase lots a folio still holds in a class, oldest first, after netting every redemption
# (paid ones — negative FundUnits — and dealt-but-unpaid fills) against the oldest lots first.
# Lock-up checks and the unit register classify THESE lots, so units already redeemed can't make a
# later lot look unlocked (review finding: lock-up ignored past redemptions).
class EvergreenLots
  # => [[issue_date, remaining_quantity], ...] with remaining_quantity > 0
  def self.remaining(capital_commitment_id, unit_type)
    remaining_for([[capital_commitment_id, unit_type]]).fetch([capital_commitment_id, unit_type])
  end

  # The same for many folios at once, in two queries rather than two per folio (the unit register).
  # pairs: [[capital_commitment_id, unit_type], ...] => { [capital_commitment_id, unit_type] => lots }
  def self.remaining_for(pairs)
    return {} if pairs.empty?

    ids = pairs.map(&:first).uniq
    unit_types = pairs.map(&:last).uniq
    # Each folio's units in issue order (the global order is kept within each group)
    units = FundUnit.where(capital_commitment_id: ids, unit_type: unit_types).order(:issue_date, :id)
                    .pluck(:capital_commitment_id, :unit_type, :issue_date, :quantity)
                    .group_by { |cc_id, unit_type, _, _| [cc_id, unit_type] }
    # Dealt-but-unpaid redemption units per folio and class
    unpaid = DealingFill.joins(:dealing_order).where(kind: "redemption", fund_unit_id: nil, unit_type: unit_types)
                        .where(dealing_orders: { capital_commitment_id: ids })
                        .group("dealing_orders.capital_commitment_id", "dealing_fills.unit_type").sum(:units)
    pairs.to_h do |pair|
      folio_units = units.fetch(pair, []).map { |_, _, issue_date, quantity| [issue_date, quantity] }
      [pair, net(folio_units, unpaid.fetch(pair, 0).to_d)]
    end
  end

  # Nets paid redemptions (negative units) and unpaid ones against the oldest purchase lots first.
  # units: [[issue_date, quantity], ...] in issue order
  def self.net(units, unpaid_redeemed)
    lots = units.select { |_, q| q.to_d.positive? }.map { |d, q| [d, q.to_d] }
    redeemed = units.sum { |_, q| q.to_d.negative? ? -q.to_d : 0 }
    redeemed += unpaid_redeemed
    lots.each_with_object([]) do |(date, qty), left|
      take = [qty, redeemed].min
      redeemed -= take
      left << [date, qty - take] if qty > take
    end
  end
end
