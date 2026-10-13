# At confirmation, orders not ready by the cut-off are rolled to the next dealing date of their kind
# (keeping their received time, so a redemption keeps its queue place) or cancelled, per the fund's
# setting; partially filled redemptions carry forward the same way. A pre-funded order's subscription
# payment moves with it. Undo restores them from the dealing date's snapshot.
# Worked examples E21, E22, E24, E25, H26 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingRoll
  # The next dealing date of the order's kind after this one
  def self.next_date(order, dealing_date)
    setting = order.fund.evergreen_fund_setting
    DealingCalendar.dates(setting, order.kind, from: dealing_date.date + 1.day, to: dealing_date.date + 2.years).first
  end

  # Move an order to the next dealing date (roll or carry-forward). Returns the new dealing date.
  def self.move(order, dealing_date, user, count_roll: true)
    nxt = DealingDate.for(order.fund, next_date(order, dealing_date))
    order.update!(dealing_date: nxt, rolled_count: order.rolled_count + (count_roll ? 1 : 0))
    move_subscription_payment(order, nxt, user) if order.capital_remittance
    refresh_early_fee(order, nxt)
    nxt
  end

  # E87: re-judge a soft lock-up at the new date, so the order shows the fee pricing will charge
  # (pricing re-judges again per lot on the day it runs)
  def self.refresh_early_fee(order, dealing_date)
    return unless order.redemption? && order.early_fee_pct.to_d.positive?

    units = order.all_units ? order.free_units : order.resolved_units
    lock = EvergreenLockUp.call(order, on: dealing_date.date, requested: units)
    order.update_columns(early_fee_pct: lock.blended_pct, locked_units: lock.locked_units)
  rescue StandardError => e
    # Never block a roll over a display figure; pricing recomputes the real fee
    Rails.logger.warn("[DealingRoll] fee refresh for order #{order.id}: #{e.message}")
  end

  # The pre-funded payment row follows the order to the next subscription settlement: re-pointed
  # with its payments when money has arrived, else recreated. Counters are fixed by the existing job.
  def self.move_subscription_payment(order, to_date, user)
    rem = order.capital_remittance
    call = DealingSettlement.subscription_call(to_date, user)
    return if rem.capital_call_id == call.id

    if rem.capital_remittance_payments.exists?
      rem.update_columns(capital_call_id: call.id)
      CapitalRemittancesCountersJob.perform_later([order.fund_id], user&.id, call.id)
    else
      DealingSettlement.remove_subscription_payment(order)
      DealingSettlement.ensure_subscription_payment(order.reload, user)
    end
  end

  # What confirmation does with an order that is not ready — ONE rule for the preview and the
  # confirm, so the preview always states the real outcome (E108):
  #   :roll   — to the next dealing date; always when money has been received for it (E108),
  #             otherwise when the fund rolls unready orders
  #   :cancel — the fund cancels unready orders and nothing was received, or no later date exists (E110)
  #   :stay   — money received but no later dealing date: left pending for the GP to refund
  # "no later redemption date in the calendar" — said the same way by the pricing preview and the
  # reason stored at confirm, in the fund's wording, so the preview states what will really happen
  def self.no_later_date(order)
    date_word = EvergreenLabels.t(order.subscription? ? :subscription_date : :redemption_date, fund: order.fund, lower: true)
    "no later #{date_word} in the calendar"
  end

  def self.fate(order, dealing_date)
    setting = dealing_date.fund.evergreen_fund_setting
    paid = order.capital_remittance&.capital_remittance_payments&.exists?
    nxt = next_date(order, dealing_date)
    return (paid ? :stay : :cancel) if nxt.nil?
    return :roll if paid

    setting.unready_handling == "cancel" ? :cancel : :roll
  end

  # Roll or cancel every order not ready at confirmation. Returns {rolled: [ids], cancelled: [ids]}.
  def self.call(dealing_date, unready_rows, user)
    result = { "rolled" => [], "cancelled" => [] }
    unready_rows.each do |row|
      order = row.order
      case fate(order, dealing_date)
      when :cancel
        no_next = next_date(order, dealing_date).nil?
        DealingSettlement.remove_subscription_payment(order)
        FolioOpener.reverse(order, user)
        order.update!(status: "cancelled", cancelled_at: Time.current,
                      rejected_reason: no_next ? "#{row.reason} — #{no_later_date(order)}" : row.reason)
        result["cancelled"] << order.id
      when :roll
        move(order, dealing_date, user)
        result["rolled"] << order.id
      end
      # :stay — money received and nowhere to roll: left pending on this date for a refund
    end
    result
  end
end
