class CapitalCommitmentAction < Trailblazer::Operation
  def set_orig_amounts(_ctx, capital_commitment:, **)
    capital_commitment.set_orig_amounts if capital_commitment.orig_folio_committed_amount_cents == 0
  end

  def set_committed_amount(_ctx, capital_commitment:, **)
    capital_commitment.set_committed_amount
  end

  def save(_ctx, capital_commitment:, **)
    capital_commitment.save
  end

  def compute_percentage(ctx, capital_commitment:, **)
    capital_commitment.compute_percentage if capital_commitment.saved_change_to_committed_amount_cents? && ctx[:import_upload].blank?
    true
  end

  def touch_investor(ctx, capital_commitment:, **)
    capital_commitment.investor.touch if ctx[:import_upload].blank? # unless capital_commitment.destroyed?
    true
  end

  def handle_errors(ctx, capital_commitment:, **)
    unless capital_commitment.valid?
      ctx[:errors] = capital_commitment.errors.full_messages.join(", ")
      Rails.logger.error capital_commitment.errors.full_messages
    end
    capital_commitment.valid?
  end
end
