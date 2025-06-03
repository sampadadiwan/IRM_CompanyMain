class AdjustmentAction < Trailblazer::Operation
  def save(_ctx, commitment_adjustment:, **)
    commitment_adjustment.save
  end

  def touch_investor(_ctx, commitment_adjustment:, **)
    # rubocop:disable Rails/SkipsModelValidations
    commitment_adjustment.capital_commitment.investor.touch # unless commitment_adjustment.destroyed?
    # rubocop:enable Rails/SkipsModelValidations
  end

  def handle_errors(ctx, commitment_adjustment:, **)
    unless commitment_adjustment.valid?
      ctx[:errors] = commitment_adjustment.errors.full_messages.join(", ")
      Rails.logger.error commitment_adjustment.errors.full_messages
    end
    commitment_adjustment.valid?
  end

  def validate(_ctx, commitment_adjustment:, **)
    commitment_adjustment.valid?
  end

  def compute_adjustments(_ctx, commitment_adjustment:, **)
    if commitment_adjustment.update_committed_amounts?
      commitment_adjustment.update_committed_amounts
      true
    elsif commitment_adjustment.update_arrear_amounts?
      commitment_adjustment.update_arrear_amounts
      true
    end
  end

  def update_commitment(_ctx, commitment_adjustment:, **)
    CapitalCommitmentUpdate.call(capital_commitment: commitment_adjustment.capital_commitment.reload).success?
  end

  def handle_commitment_errors(ctx, commitment_adjustment:, **)
    capital_commitment = commitment_adjustment.capital_commitment
    unless capital_commitment.valid?
      ctx[:errors] = capital_commitment.errors.full_messages.join(", ")
      Rails.logger.error capital_commitment.errors.full_messages
    end
    capital_commitment.valid?
  end

  def update_owner(_ctx, commitment_adjustment:, **)
    CapitalRemittanceUpdate.call(capital_remittance: commitment_adjustment.owner.reload).success? if commitment_adjustment.owner_type == "CapitalRemittance"
    true
  end
end
