class CapitalCommitmentUpdate < CapitalCommitmentAction
  step :set_orig_amounts
  step :set_committed_amount
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :update_folio_id
  step :compute_percentage
  step :touch_investor

  def update_folio_id(_ctx, capital_commitment:, **)
    capital_commitment.update_folio_id if capital_commitment.saved_change_to_folio_id?
    true
  end
end
