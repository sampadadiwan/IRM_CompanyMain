class AdjustmentCreate < AdjustmentAction
  step :validate
  step :compute_adjustments
  step :save
  left :handle_errors
  step :update_commitment
  step :update_owner
  step :touch_investor

  def validate(_ctx, commitment_adjustment:, **)
    if commitment_adjustment.owner_type == "CapitalRemittance"
      commitment_adjustment.owner.folio_id == commitment_adjustment.capital_commitment.folio_id && commitment_adjustment.valid?
    else
      commitment_adjustment.valid?
    end
  end

  def compute_adjustments(ctx, commitment_adjustment:, **)
    if commitment_adjustment.update_committed_amounts?
      commitment_adjustment.update_committed_amounts
      true
    elsif commitment_adjustment.update_arrear_amounts?
      commitment_adjustment.update_arrear_amounts
      true
    else
      ctx[:errors] = "Invalid adjustment type"
      false
    end
  end

  def update_commitment(_ctx, commitment_adjustment:, **)
    CapitalCommitmentUpdate.call(capital_commitment: commitment_adjustment.capital_commitment.reload).success?
  end

  def update_owner(_ctx, commitment_adjustment:, **)
    CapitalRemittanceUpdate.call(capital_remittance: commitment_adjustment.owner.reload).success? if commitment_adjustment.owner_type == "CapitalRemittance"
    true
  end
end
