class SecondarySaleAction < Trailblazer::Operation
  def save(ctx, secondary_sale:, **)
    validate = ctx[:investor_user]
    secondary_sale.save(validate:)
  end

  def handle_errors(ctx, secondary_sale:, **)
    unless secondary_sale.valid?
      ctx[:errors] = secondary_sale.errors
      Rails.logger.error("Errors: #{secondary_sale.errors.full_messages}")
    end
    secondary_sale.valid?
  end
end
