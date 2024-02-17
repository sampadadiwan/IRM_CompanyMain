class CapitalRemittanceCreate < CapitalRemittanceAction
  step :set_call_amount
  step :save
  left :handle_errors
  step :touch_investor
end
