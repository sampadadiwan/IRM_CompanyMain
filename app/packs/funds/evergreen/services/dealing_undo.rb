# Undoes a confirmed dealing date while nothing has settled: removes its settlement records and
# fills, and returns its orders (including those rolled, carried or cancelled at confirm) to pending
# on this dealing date.
# Worked examples E33, X18 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingUndo < Trailblazer::Operation
  step :check
  step :undo

  def check(ctx, dealing_date:, **)
    ctx[:errors] = if !dealing_date.confirmed? then "Only a confirmed #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: dealing_date.fund))} can be undone"
                   elsif dealing_date.settlement_started? then "#{EvergreenLabels.t(:Units, fund: dealing_date.fund)} allotted or payments recorded — reverse them first"
                   elsif moved_orders_dealt_later?(dealing_date)
                     "Orders moved on from this date have since been dealt on a later date — undo that date first"
                   end
    ctx[:errors].nil?
  end

  def undo(ctx, dealing_date:, current_user:, **)
    ActiveRecord::Base.transaction do
      dealing_date.lock!
      snapshot = dealing_date.gate_snapshot || {}
      DealingSettlement.unsettle(dealing_date, current_user)
      order_ids = dealing_date.dealing_fills.pluck(:dealing_order_id)
      dealing_date.dealing_fills.destroy_all
      restore(order_ids, dealing_date, current_user, roll_back: false)
      restore(Array(snapshot.dig("rolled", "rolled")), dealing_date, current_user, roll_back: true)
      restore(Array(snapshot.dig("rolled", "cancelled")), dealing_date, current_user, roll_back: false, reopen: true)
      dealing_date.update!(status: "open", confirmed_by: nil, confirmed_at: nil, gate_snapshot: nil, settings_snapshot: nil)
    end
    dealing_date.journey_progress!(actor: current_user)
    true
  # Review fix 5b: restoring a pre-funded subscription that confirm cancelled (it had lost its payment
  # row) re-opens its folio through FolioOpener (#restore), which raises FolioOpener::Error when the
  # folio or its top-up can't be saved — refuse the undo with that message (the transaction rolls
  # back) instead of an unhandled error, as DealingConfirm already does
  rescue DealingSettlement::Error, FolioOpener::Error => e
    ctx[:errors] = e.message
    false
  end

  private

  # Orders rolled or carried at confirm that now sit on a later confirmed / closed dealing date
  def moved_orders_dealt_later?(dealing_date)
    ids = Array(dealing_date.gate_snapshot.to_h.dig("rolled", "rolled")) + dealing_date.dealing_fills.where("carried_units > 0").pluck(:dealing_order_id)
    DealingOrder.where(id: ids).where.not(dealing_date_id: dealing_date.id).joins(:dealing_date)
                .exists?(dealing_dates: { status: %w[confirmed closed] })
  end

  def restore(order_ids, dealing_date, user, roll_back:, reopen: false)
    DealingOrder.where(id: order_ids).find_each do |order|
      # Leave alone orders changed since the confirm: cancelled or dealt elsewhere afterwards
      next if !reopen && order.dealing_date_id != dealing_date.id && !order.open?

      attrs = { status: "pending", dealing_date_id: dealing_date.id }
      attrs[:rolled_count] = [order.rolled_count - 1, 0].max if roll_back
      if reopen
        attrs[:cancelled_at] = nil
        attrs[:rejected_reason] = nil
      end
      order.update!(attrs)
      next unless order.subscription? && dealing_date.pre_funded?

      # The pre-funded payment row (and folio) come back to this dealing date's settlement
      if order.capital_remittance
        DealingRoll.move_subscription_payment(order, dealing_date, user)
      else
        FolioOpener.call(order, user)
        DealingSettlement.ensure_subscription_payment(order.reload, user)
      end
    end
  end
end
