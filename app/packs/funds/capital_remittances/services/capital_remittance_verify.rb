class CapitalRemittanceVerify < CapitalRemittanceAction
  step :set_call_amount
  step :toggle_verify
  step :save
  left :handle_errors
  step :payment_received_notification
  step :touch_investor

  def toggle_verify(_ctx, capital_remittance:, **)
    capital_remittance.verified = !capital_remittance.verified
  end

  def payment_received_notification(_ctx, capital_remittance:, **)
    capital_remittance.payment_received_notification if capital_remittance.verified
  end
end
