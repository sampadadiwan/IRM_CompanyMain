class CancelHolding < HoldingAction
  step :cancel_holding
  left :handle_error
  step :notify_holding_cancellation
  step :update_trust_holdings

  def cancel_holding(ctx, holding:, all_or_unvested:, **)
    case all_or_unvested
    when "all"
      unvested_cancelled_quantity = holding.unvested_cancelled_quantity + holding.net_unvested_quantity
      unexcercised_cancelled_quantity = holding.unexcercised_cancelled_quantity + holding.net_avail_to_excercise_quantity

      holding.update(cancelled: true, unvested_cancelled_quantity:,
                     unexcercised_cancelled_quantity:,
                     audit_comment: "#{ctx[:audit_comment]} : Cancelled All")
    # puts "### all Calling compute_vested_quantity #{holding.vested_quantity}"
    when "unvested"
      unvested_cancelled_quantity = holding.unvested_cancelled_quantity + holding.net_unvested_quantity
      holding.update(cancelled: true, unvested_cancelled_quantity:,
                     audit_comment: "#{ctx[:audit_comment]} : Cancelled Unvested")
    # puts "### unvested Calling compute_vested_quantity #{holding.vested_quantity}"
    when "custom"
      unexcercised_cancelled_quantity = holding.unexcercised_cancelled_quantity + context.shares_to_sell
      holding.update(cancelled: true, unexcercised_cancelled_quantity:,
                     audit_comment: "#{ctx[:audit_comment]} : Cancelled for Cashless Excercise")
    else
      holding.errors.add(:cancelled, "Invalid option provided, all or unvested only")
      false
    end
  end

  def notify_holding_cancellation(_ctx, holding:, **)
    holding.reload.notify_cancellation
    true
  end
end
