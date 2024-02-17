class CapitalCommitmentAction < Trailblazer::Operation
  def set_committed_amount(_ctx, capital_commitment:, **)
    capital_commitment.set_committed_amount
  end

  def save(_ctx, capital_commitment:, **)
    capital_commitment.save
  end

  def compute_percentage(_ctx, capital_commitment:, **)
    capital_commitment.compute_percentage if capital_commitment.saved_change_to_committed_amount_cents?
    true
  end

  def touch_investor(_ctx, capital_commitment:, **)
    capital_commitment.investor.touch # unless capital_commitment.destroyed?
  end

  def handle_errors(ctx, capital_commitment:, **)
    ctx[:errors] = capital_commitment.errors unless capital_commitment.valid?
    capital_commitment.valid?
  end
end
