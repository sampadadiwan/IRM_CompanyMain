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
    true
  end

  def setup_call_fees(_ctx, capital_remittance:, **)
    capital_remittance.setup_call_fees
    true
  end

  def set_status(_ctx, capital_remittance:, **)
    capital_remittance.set_status
    true
  end

  def touch_investor(_ctx, capital_remittance:, **)
    capital_remittance.touch_investor
  end

  def set_payment_date(_ctx, capital_remittance:, **)
    capital_remittance.set_payment_date
    true
  end
end
