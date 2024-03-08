class InterestAction < Trailblazer::Operation
  def save(ctx, interest:, **)
    validate = ctx[:investor_user]
    interest.save(validate:)
  end

  def handle_errors(ctx, interest:, **)
    unless interest.valid?
      ctx[:errors] = interest.errors.full_messages.join(", ")
      Rails.logger.error("Errors: #{interest.errors.full_messages}")
    end
    interest.valid?
  end
end
