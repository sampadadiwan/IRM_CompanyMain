class CapitalCallUnapprove < CapitalCallAction
  step :reset_approval
  step :save
  left :handle_errors, Output(:failure) => End(:failure)

  def reset_approval(_ctx, capital_call:, **)
    capital_call.approved = false
    capital_call.approved_by_user = nil
    true
  end
end
