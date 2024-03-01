class CapitalCallAction < Trailblazer::Operation
  def save(_ctx, capital_call:, **)
    capital_call.save
  end

  def handle_errors(ctx, capital_call:, **)
    ctx[:errors] = capital_call.errors.full_messages unless capital_call.valid?
    capital_call.valid?
  end

  def generate_capital_remittances(_ctx, capital_call:, **)
    capital_call.generate_capital_remittances unless capital_call.destroyed?
    true
  end

  def send_notification(_ctx, capital_call:, **)
    capital_call.send_notification if capital_call.approved
    true
  end
end
