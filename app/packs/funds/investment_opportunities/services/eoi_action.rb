class EoiAction < Trailblazer::Operation
  def save(_ctx, expression_of_interest:, **)
    expression_of_interest.save
  end

  def handle_errors(ctx, expression_of_interest:, **)
    unless expression_of_interest.valid?
      ctx[:errors] = expression_of_interest.errors.full_messages.join(", ")
      Rails.logger.error expression_of_interest.errors.full_messages
    end
    expression_of_interest.valid?
  end
end
