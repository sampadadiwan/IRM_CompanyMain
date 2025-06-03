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

  # This creates the offsetting payment for the adjustment
  def create_reverse_payment(_ctx, commitment_adjustment:, **)
    if commitment_adjustment.owner_type == "CapitalRemittance"
      capital_remittance = commitment_adjustment.owner
      capital_remittance.capital_remittance_payments.create(entity_id: capital_remittance.entity_id, fund_id: capital_remittance.fund_id, capital_remittance_id: capital_remittance.id, amount_cents: commitment_adjustment.amount_cents, folio_amount_cents: commitment_adjustment.folio_amount_cents, payment_date: commitment_adjustment.as_of, notes: "Created by adjustment #{commitment_adjustment.id}")
    end
    true
  end
end
