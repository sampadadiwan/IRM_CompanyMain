# Very similar to OfferAllocate
class OfferVerify < OfferAction
  step :verify
  step :save
  left :handle_errors
  step :generate_spa
  step :notify_accept_spa

  def verify(_ctx, offer:, **)
    offer.verified = true
  end
end
