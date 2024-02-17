class CapitalCallUpdate < CapitalCallAction
  step :save
  left :handle_errors
  step :generate_capital_remittances
  step :send_notification
end
