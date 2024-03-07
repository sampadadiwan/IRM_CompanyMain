class CapitalCommitmentCreate < CapitalCommitmentAction
  step :set_committed_amount
  step :save
  left :handle_errors
  step :give_access_rights
  step :create_remittance
  step :compute_percentage
  step :touch_investor

  def create_remittance(_ctx, capital_commitment:, **)
    if capital_commitment.fund.capital_calls.count.positive?
      # If we have pre existing calls, then we need to generate the remittances for those.
      CapitalCommitmentRemittanceJob.perform_later(capital_commitment.id)
    end
    true
  end

  def give_access_rights(_ctx, capital_commitment:, **)
    AccessRight.create(entity_id: capital_commitment.entity_id, owner: capital_commitment.fund, investor: capital_commitment.investor, access_type: "Fund", metadata: "Investor")
    true
  end
end
