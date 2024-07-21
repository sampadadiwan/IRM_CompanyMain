class CapitalRemittanceCreate < CapitalRemittanceAction
  step :set_call_amount
  step :setup_call_fees
  step :set_status
  step :set_payment_date
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :touch_investor
end
