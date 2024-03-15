class CapitalCallAction < Trailblazer::Operation
  def save(_ctx, capital_call:, **)
    capital_call.save
  end

  def handle_errors(ctx, capital_call:, **)
    unless capital_call.valid?
      ctx[:errors] = capital_call.errors.full_messages.join(", ")
      Rails.logger.error capital_call.errors.full_messages
    end
    capital_call.valid?
  end

  def generate_capital_remittances(ctx, capital_call:, **)
    # If this is called via import of calls, then we don't want to generate remittances in poerform_later but we want to generate in perform_now. if import_upload is not present, then later is false.
    later = ctx[:import_upload].blank?
    capital_call.generate_capital_remittances(later:) unless capital_call.destroyed?
    true
  end

  def send_notification(_ctx, capital_call:, **)
    capital_call.send_notification if capital_call.approved
    true
  end
end
