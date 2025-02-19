class AdjustmentCreate < AdjustmentAction
  step :validate
  step :compute_adjustments
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :create_reverse_payment
  step :update_commitment
  left :handle_commitment_errors
  step :update_owner
  step :touch_investor

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

  # This creates the offsetting payment for the adjustment
  def create_reverse_payment(_ctx, commitment_adjustment:, **)
    if commitment_adjustment.owner_type == "CapitalRemittance"
      capital_remittance = commitment_adjustment.owner
      capital_remittance.capital_remittance_payments.create(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_remittance_id: capital_remittance.id, amount_cents: commitment_adjustment.amount_cents, folio_amount_cents: commitment_adjustment.folio_amount_cents, payment_date: commitment_adjustment.as_of, notes: "Created by adjustment #{commitment_adjustment.id}")
    end
    true
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
