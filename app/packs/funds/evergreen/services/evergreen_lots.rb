# The purchase lots a folio still holds in a class, oldest first, after netting every redemption
# (paid ones — negative FundUnits — and dealt-but-unpaid fills) against the oldest lots first.
# Lock-up checks and the unit register classify THESE lots, so units already redeemed can't make a
# later lot look unlocked (review finding: lock-up ignored past redemptions).
class EvergreenLots
  # => [[issue_date, remaining_quantity], ...] with remaining_quantity > 0
  def self.remaining(capital_commitment_id, unit_type)
    units = FundUnit.where(capital_commitment_id:, unit_type:).order(:issue_date, :id).pluck(:issue_date, :quantity)
    lots = units.select { |_, q| q.to_d.positive? }.map { |d, q| [d, q.to_d] }
    redeemed = units.sum { |_, q| q.to_d.negative? ? -q.to_d : 0 }
    redeemed += DealingFill.joins(:dealing_order).where(kind: "redemption", fund_unit_id: nil, unit_type:)
                           .where(dealing_orders: { capital_commitment_id: }).sum(:units).to_d
    lots.each_with_object([]) do |(date, qty), left|
      take = [qty, redeemed].min
      redeemed -= take
      left << [date, qty - take] if qty > take
    end
  end
end
