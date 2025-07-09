class CapitalRemittancePaymentAction < Trailblazer::Operation
  def save(_ctx, capital_remittance_payment:, **)
    capital_remittance_payment.save
  end

  def handle_errors(ctx, capital_remittance_payment:, **)
    unless capital_remittance_payment.errors.blank? && capital_remittance_payment.valid?
      ctx[:errors] = capital_remittance_payment.errors.full_messages.join(", ")
      Rails.logger.error "Capital remittance Payment errors: #{capital_remittance_payment.errors.full_messages}"
    end
    capital_remittance_payment.errors.blank? && capital_remittance_payment.valid?
  end

  def set_amount(_ctx, capital_remittance_payment:, **)
    capital_remittance_payment.set_amount if capital_remittance_payment.folio_amount_cents_changed? && capital_remittance_payment.convert_to_fund_currency
    true
  end

  def destroy(_ctx, capital_remittance_payment:, **)
    begin
      capital_remittance_payment.destroy
    rescue e
      Rails.logger.error "Error destroying capital remittance payment: #{e.message}"
    end
    capital_remittance_payment.errors.blank?
  end
end
