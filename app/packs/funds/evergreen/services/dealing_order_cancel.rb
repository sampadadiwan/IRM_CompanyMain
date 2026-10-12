# Cancels a pending order whose dealing date is not confirmed: removes its unpaid subscription
# payment, reverses its folio top-up, and emails "Request cancelled".
# Worked examples H11, E17, E20 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingOrderCancel < Trailblazer::Operation
  step :check
  step :cancel
  step :notify

  def check(ctx, order:, **)
    ctx[:errors] = if !order.pending? then "Only a pending order can be cancelled"
                   elsif !order.dealing_date.open? then "The #{EvergreenLabels.lower(EvergreenLabels.t(order.subscription? ? :subscription_date : :redemption_date, fund: order.fund))} is confirmed — this order can no longer be cancelled"
                   elsif order.capital_remittance&.capital_remittance_payments&.exists? then "Money has been received for this order — refund it before cancelling"
                   end
    ctx[:errors].nil?
  end

  def cancel(_ctx, order:, current_user:, reason: nil, status: "cancelled", **)
    ActiveRecord::Base.transaction do
      order.lock!
      DealingSettlement.remove_subscription_payment(order)
      FolioOpener.reverse(order, current_user)
      order.update!(status:, cancelled_by: current_user, cancelled_at: Time.current, rejected_reason: reason)
    end
    true
  end

  def notify(_ctx, order:, **)
    EvergreenNotifier.order_cancelled(order)
    true
  end
end
