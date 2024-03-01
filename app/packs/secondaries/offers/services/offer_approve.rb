class OfferApprove < OfferAction
  step :approve
  left :handle_errors
  # step :notify_accept_spa

  def approve(ctx, offer:, current_user:, **)
    offer.approved = !offer.approved
    ctx[:label] = offer.approved ? "approved" : "unapproved"
    offer.granted_by_user_id = current_user.id
    offer.save
  end
end
