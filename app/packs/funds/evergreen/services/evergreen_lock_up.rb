# Lock-up of a redemption, judged per purchase lot on a given dealing date (§ Lock-ups).
# The folio's lots (after netting past redemptions, EvergreenLots) are used oldest first: free lots
# first, then locked lots oldest first. Each locked lot used pays the early-redemption fee for ITS
# OWN age (E86), and the judgement is made on the date the order is actually dealt, so a roll or
# carry past an unlock date drops the fee (E87).
# Worked examples E5, E16, E80–E87, X14, X40–X44 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenLockUp
  # locked: [[units, fee_pct, unlocks_on], ...] for the locked units this request uses, oldest first
  Result = Data.define(:locked) do
    def locked_units = locked.sum { |u, _, _| u }

    # Units-weighted fee % (what the order stores and shows); 0 when nothing locked is used
    def blended_pct
      units = locked_units
      units.positive? ? (locked.sum { |u, pct, _| u * pct } / units).round(4) : 0.to_d
    end

    # Fee in cents at a NAV per unit — each lot at its own rate (E86)
    def fee_cents(nav_per_unit_cents)
      locked.sum { |u, pct, _| u * nav_per_unit_cents.to_d * pct / 100 }.round(2)
    end

    # The date the LAST locked unit used unlocks — when the whole request could be met (X40, X44)
    def locked_until = locked.map(&:last).max

    # "100 at 3%, 100 at 2%" — only when lots pay different rates
    def breakdown
      rates = locked.group_by { |_, pct, _| pct }.transform_values { |ls| ls.sum(&:first) }
      rates.size > 1 ? rates.map { |pct, u| "#{fmt(u)} at #{fmt(pct)}%" }.join(", ") : nil
    end

    private

    def fmt(value) = ActiveSupport::NumberHelper.number_to_delimited(value.to_d.round(4).to_s("F").sub(/\.?0+\z/, ""))
  end

  # requested: units this order redeems; queued: units of the folio's other open redemptions, which
  # are assumed to take the free units first
  def self.call(order, on:, requested:, queued: 0)
    term = order.fund.evergreen_fund_setting.terms_for(order.unit_type)
    return Result.new(locked: []) unless order.redemption? && term.lock_up? && order.capital_commitment_id

    unlocks = ->(issued) { issued.advance(months: term.lock_up_months) }
    lots = EvergreenLots.remaining(order.capital_commitment_id, order.unit_type)
    # A lot unlocking ON the dealing date is free (E81); one day later is locked (X42)
    locked_lots, free_lots = lots.partition { |issued, _| unlocks.call(issued) > on }
    free = free_lots.sum { |_, q| q } - queued.to_d
    needed = [requested.to_d - [free, 0].max, 0].max
    # Use the locked lots oldest first until the request is met
    used = locked_lots.each_with_object([]) do |(issued, qty), out|
      break out unless needed.positive?

      take = [qty, needed].min
      needed -= take
      age = ((on - issued) / 30.4375).floor
      out << [take, term.hard_lock_up? ? 0.to_d : term.early_fee_pct_for(age), unlocks.call(issued)]
    end
    Result.new(locked: used)
  end
end
