class CapitalRemittanceUpdate < CapitalRemittanceAction
  step :setup_call_fees
  step :set_call_amount
  step :set_status
  step :save
  left :handle_errors
  step :touch_investor
end
