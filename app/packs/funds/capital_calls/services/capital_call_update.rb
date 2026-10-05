class CapitalCallUpdate < CapitalCallAction
  step :start_journey_undo
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_capital_remittances
  step :cascade_call_date_change
  step :invalidate_if_figures_changed
end
