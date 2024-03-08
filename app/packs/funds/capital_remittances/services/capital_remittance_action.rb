class CapitalRemittanceAction < Trailblazer::Operation
  def save(_ctx, capital_remittance:, **)
    capital_remittance.save
  end

  def handle_errors(ctx, capital_remittance:, **)
    unless capital_remittance.valid?
      ctx[:errors] = capital_remittance.errors.full_messages.join(", ")
      Rails.logger.error "Capital remittance errors: #{capital_remittance.errors.full_messages}"
    end
    capital_remittance.valid?
  end

  def set_call_amount(_ctx, capital_remittance:, **)
    capital_remittance.set_call_amount
  end

  def touch_investor(_ctx, capital_remittance:, **)
    capital_remittance.touch_investor
  end
end
