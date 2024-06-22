class OfferAcceptSpa < OfferAction
  step :accept_spa
  left :handle_errors, Output(:failure) => End(:failure)
  step :notify_accept_spa

  def accept_spa(_ctx, offer:, current_user:, **)
    offer.final_agreement = true
    offer.final_agreement_user_id = current_user.id
    offer.save
  end
end
