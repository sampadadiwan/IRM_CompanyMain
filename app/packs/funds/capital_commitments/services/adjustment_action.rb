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
end
