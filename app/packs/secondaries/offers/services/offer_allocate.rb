class OfferAllocate < OfferAction
  step :allocate
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_spa
  left :handle_spa_errors, Output(:failure) => End(:failure)
  step :notify_accept_spa

  def allocate(_ctx, offer:, offer_params:, **)
    offer.allocation_quantity = offer_params[:allocation_quantity]
    offer.comments = offer_params[:comments]
    offer.verified = offer_params[:verified]
    offer.interest_id = offer_params[:interest_id]
  end
end
