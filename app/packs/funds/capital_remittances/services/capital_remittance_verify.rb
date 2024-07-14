class CapitalRemittanceVerify < CapitalRemittanceAction
  step :setup_call_fees
  step :set_call_amount
  step :set_status
  step :toggle_verify
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :payment_received_notification
  step :touch_investor

  def toggle_verify(_ctx, capital_remittance:, **)
    if capital_remittance.collected_amount_cents.positive?
      capital_remittance.verified = !capital_remittance.verified
      true
    else
      capital_remittance.errors.add(:collected_amount_cents, "must be greater than 0 for verification")
      false
    end
  end

  def payment_received_notification(_ctx, capital_remittance:, **)
    capital_remittance.payment_received_notification if capital_remittance.verified
  end
end
