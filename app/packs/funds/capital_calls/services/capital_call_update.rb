class CapitalCallUpdate < CapitalCallAction
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances
  step :cascade_call_date_change
end
