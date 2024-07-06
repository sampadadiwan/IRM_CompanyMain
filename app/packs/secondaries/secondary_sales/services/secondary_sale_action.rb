class SecondarySaleAction < Trailblazer::Operation
  def save(ctx, secondary_sale:, **)
    validate = ctx[:investor_user]
    secondary_sale.save(validate:)
  end

  def handle_errors(ctx, secondary_sale:, **)
    unless secondary_sale.valid?
      ctx[:errors] = secondary_sale.errors.full_messages.join(", ")
      Rails.logger.error("Errors: #{secondary_sale.errors.full_messages}")
    end
    secondary_sale.valid?
  end

  # Run allocation if the sale is finalized and price is changed
  def allocate_sale(_ctx, secondary_sale:, current_user:, **)
    secondary_sale.allocate_sale(current_user.id) if secondary_sale.finalized && secondary_sale.final_price_changed?
    true
  end
end
