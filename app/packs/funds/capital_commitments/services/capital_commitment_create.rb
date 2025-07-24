class CapitalCommitmentCreate < CapitalCommitmentAction
  step :set_orig_amounts
  step :set_committed_amount
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :give_access_rights
  step :compute_percentage
  step :touch_investor
  step :create_remittance

  def create_remittance(ctx, capital_commitment:, **)
    if capital_commitment.fund.capital_calls.any? && ctx[:import_upload].blank?
      # If we have pre existing calls, then we need to generate the remittances for those.
      CapitalCommitmentRemittanceJob.perform_later(capital_commitment.id)
    end
    true
  end

  def give_access_rights(ctx, capital_commitment:, **)
    # Note that when commitments are imported this causes deadlock issues
    # ImportCapitalCommitment will handle this at the end of the import
    capital_commitment.grant_access_to_fund if ctx[:import_upload].blank?
    true
  end
end
