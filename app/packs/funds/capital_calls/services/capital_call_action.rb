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

  # Editing call_date after remittances already exist re-dates every capital_remittance to match
  # (see docs/technical/call_and_distribution_date_cascade_plan.md) and triggers a fee recompute,
  # since the new date changes the exchange-rate lookup used for fee/amount conversions.
  def cascade_call_date_change(_ctx, capital_call:, current_user: nil, **)
    CapitalCallDateChangeJob.perform_later(capital_call.id, current_user.id) if capital_call.saved_change_to_call_date? && current_user
    true
  end
end
