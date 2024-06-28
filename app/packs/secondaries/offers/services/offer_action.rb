class OfferAction < Trailblazer::Operation
  def save(_ctx, offer:, current_user:, **)
    offer.user_id ||= current_user.id
    offer.entity_id = offer.secondary_sale.entity_id
    offer.save
  end

  def handle_errors(ctx, offer:, **)
    unless offer.valid?
      ctx[:errors] = offer.errors.full_messages.join(", ")
      Rails.logger.error("Errors: #{offer.errors.full_messages}")
    end
    offer.valid?
  end

  def handle_spa_errors(ctx, offer:, **)
    offer.errors.clear
    offer.validate_spa_generation
    if offer.errors.any?
      ctx[:errors] = offer.errors.full_messages.join(", ")
      Rails.logger.error("Errors: #{offer.errors.full_messages}")
    end
    offer.errors.none?
  end

  def validate_pan_card(_ctx, offer:, **)
    offer.validate_pan_card unless offer.secondary_sale.disable_pan_kyc
    true
  end

  def validate_bank(_ctx, offer:, **)
    offer.validate_bank unless offer.secondary_sale.disable_bank_kyc
    true
  end

  def generate_spa(ctx, offer:, **)
    if offer.verified # offer.final_agreement && offer.saved_change_to_final_agreement?
      offer.generate_spa(ctx[:current_user])
    else
      true
    end
  end

  def notify_accept_spa(_ctx, offer:, **)
    offer.notify_accept_spa if offer.final_agreement && offer.saved_change_to_final_agreement?
    true
  end
end
