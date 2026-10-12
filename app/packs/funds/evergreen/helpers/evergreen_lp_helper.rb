# Investor (LP) screens of an evergreen fund — shared by the portal card and the fund page.
# Worked examples H37, E48, E172, E173, E174 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenLpHelper
  # Units of a register row the investor can redeem now: hard-locked units (E48, E174) and units
  # already queued for redemption (E173) are not free; soft-locked units are, with a fee (E172)
  def eg_free_units(row, terms)
    [row.units - (terms.hard_lock_up? ? row.locked_units : 0) - row.queued_units, 0].max
  end

  # Why Redeem is disabled for a row with nothing free, or nil when it is enabled (or there is
  # nothing held). Mirrors eg_free_units: only a hard lock-up blocks, plus units already queued.
  # "All your units are locked until 02 November 2027" when the lock-up alone blocks (E48, X115)
  def eg_redeem_blocked_reason(row, terms, fund)
    return nil if row.nil? || eg_free_units(row, terms).positive? || !row.units.to_d.positive?

    # Soft-locked units stay redeemable, so only a hard lock-up counts as locked here
    locked = terms.hard_lock_up? ? row.locked_units.to_d : 0
    queued = row.queued_units.to_d
    lock_date = row.locked_until && l(row.locked_until, format: :day_month_year)
    return "All your #{eg_t(:units, fund:)} are locked until #{lock_date}" if locked.positive? && !queued.positive?

    parts = []
    parts << "#{eg_units(locked, fund:, strip_insignificant_zeros: true)} locked until #{lock_date}" if locked.positive?
    parts << "#{eg_units(queued, fund:, strip_insignificant_zeros: true)} already queued for redemption" if queued.positive?
    parts.join("; ").presence
  end

  # An order the investor still has something to wait for: open, or dealt but its units not yet
  # allotted (pay-after subscription) or its redemption not yet paid. The Requests tab lists these
  # by default; settled and cancelled ones only under "Show all"
  def eg_lp_order_in_progress?(order)
    return true if order.open?
    return false unless order.status == "dealt"

    order.dealing_fills.any? do |f|
      order.subscription? ? f.fund_unit_id.nil? : (f.units.to_d.positive? && !f.capital_distribution_payment&.completed)
    end
  end

  # NAV per unit with the fund's currency symbol (₹10,220.00), as in the investor emails
  def eg_nav_money(cents, fund)
    cents.nil? ? "—" : evergreen_money(cents, fund)
  end

  # An investor's view of one fill's settlement — plain outcome only. The staff partial (_fill_status /
  # _document_state) carries GP instructions ("Mark it paid…", "Regenerate", "hidden from the investor")
  # and failed-generation states that must not reach an investor.
  def eg_lp_fill_status(fill)
    fund = fill.fund
    if fill.subscription?
      if fill.fund_unit_id
        eg_badge(:green, "check", "#{eg_word(:Units, fund)} allotted", "Issued to your #{EvergreenLabels.lower(eg_word(:capital_commitment, fund))}.")
      elsif fill.dealing_order.fully_paid?
        eg_badge(:blue, "cash", "Payment received", "Your #{eg_word(:units, fund)} are being issued.")
      elsif fill.dealing_order.part_paid?
        eg_badge(:blue, "cash", "Part paid", "#{eg_word(:Units, fund)} are issued once the full amount arrives.")
      else
        eg_badge(:grey, "cash-off", "Awaiting your payment", "See the payment instructions emailed to you.")
      end
    elsif fill.units.to_d.zero?
      eg_badge(:grey, "arrow-forward", eg_word(:carried, fund), "Moved to the next #{EvergreenLabels.lower(eg_word(:redemption_date, fund))}.")
    elsif fill.fund_unit_id || fill.capital_distribution_payment&.completed
      eg_badge(:green, "check", "Paid", "The proceeds have been paid to you.")
    else
      eg_badge(:blue, "clock", "Payment being processed", "The proceeds are paid after the #{EvergreenLabels.lower(eg_word(:redemption_date, fund))}.")
    end
  end
end
