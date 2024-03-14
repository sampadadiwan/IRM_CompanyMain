class CapitalRemittanceCreate < CapitalRemittanceAction
  step :setup_call_fees
  step :set_call_amount
  step :save
  left :handle_errors
  step :touch_investor
end
