class CapitalCallUnapprove < CapitalCallAction
  step :start_journey_undo
  step :reset_approval
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :evaluate_journey_undo

  def reset_approval(ctx, capital_call:, current_user: nil, **)
    ctx[:journey_undo_note] = "Unapproved by #{current_user&.full_name || 'a user'}"
    capital_call.approved = false
    capital_call.approved_by_user = nil
    true
  end
end
