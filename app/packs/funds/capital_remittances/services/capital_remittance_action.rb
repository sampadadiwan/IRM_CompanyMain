class CapitalRemittanceAction < Trailblazer::Operation
  def save(_ctx, capital_remittance:, **)
    capital_remittance.save
  end

  def handle_errors(ctx, capital_remittance:, **)
    ctx[:errors] = capital_remittance.errors unless capital_remittance.valid?
    capital_remittance.valid?
  end

  def set_call_amount(_ctx, capital_remittance:, **)
    capital_remittance.set_call_amount
  end

  def touch_investor(_ctx, capital_remittance:, **)
    capital_remittance.touch_investor
  end
end
