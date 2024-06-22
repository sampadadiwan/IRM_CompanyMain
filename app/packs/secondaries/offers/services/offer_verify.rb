# Very similar to OfferAllocate
class OfferVerify < OfferAction
  step :verify
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :generate_spa
  step :notify_accept_spa

  def verify(_ctx, offer:, **)
    offer.verified = true
  end
end
