class InterestAction < Trailblazer::Operation
  def save(ctx, interest:, **)
    validate = ctx[:investor_user]
    interest.save(validate:)
  end

  def validate_pan_card(_ctx, interest:, **)
    interest.validate_pan_card unless interest.secondary_sale.disable_pan_kyc
    true
  end

  def validate_bank(_ctx, interest:, **)
    interest.validate_bank unless interest.secondary_sale.disable_bank_kyc
    true
  end

  def handle_errors(ctx, interest:, **)
    unless interest.valid?
      ctx[:errors] = interest.errors.full_messages.join(", ")
      Rails.logger.error("Errors: #{interest.errors.full_messages}")
    end
    interest.valid?
  end
end
