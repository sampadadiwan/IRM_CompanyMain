class CapitalRemittanceVerify < CapitalRemittanceAction
  # Note: fees are NOT recomputed on verify/unverify. They are set on create/update
  # (CapitalRemittanceCreate/CapitalRemittanceUpdate), and verifying must not
  # overwrite them if account entries or fee formulas changed since then.
  step :set_call_amount
  step :toggle_verify
  step :set_status
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :payment_received_notification
  step :touch_investor

  def toggle_verify(_ctx, capital_remittance:, **)
    capital_remittance.verified = !capital_remittance.verified
    true
  end

  def payment_received_notification(_ctx, capital_remittance:, **)
    # removed checks from here as they are already present in the model
    # Here we will have to send out the notifications for the remittance_payments and not remittance
    capital_remittance.capital_remittance_payments.each(&:notify_capital_remittance_payment)
    true
  end
end
