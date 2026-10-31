class OffersBulkActionJob < BulkActionJob
  # H6 step 3 — bulk_action → the policy query each row is checked with. Verify / unverify use the
  # record bulk_actions? (update access on the sale): update? itself is false once an offer is verified,
  # so it would block unverify. Generate SPA is generate_docs?, as on the offer's own button.
  ACTIONS = { "verify" => :bulk_actions?, "unverify" => :bulk_actions?, "generate spa" => :generate_docs? }.freeze

  def perform_action(offer, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on Offer #{offer.id} - #{params}")
    msg = "#{bulk_action}: Offer #{offer.id}"
    send_notification(msg, user_id, :success)

    # H6 step 3 — per row: an LP (or a user without update on the sale) changes nothing and gets a
    # "Not authorized" line in the errors email. Tests H6-H3, H6-S2, H6-S3 —
    # features/security/bulk_actions_authorization.feature
    query = ACTIONS[bulk_action.to_s.downcase]
    if query && !Pundit.policy!(@user, offer).public_send(query)
      @error_msg << { msg: "Not authorized to #{bulk_action.to_s.downcase}", offer_id: offer.id, user: offer.user }
      return
    end

    case bulk_action.downcase

    when "verify"
      result = OfferVerify.call(offer:, current_user: User.find(user_id))
      send_notification(result[:errors], user_id, :error) if result.failure?
    when "unverify"
      offer.update(verified: false)
    when "generate spa"
      offer.validate_spa_generation
      if offer.errors.present?
        offer.errors.full_messages.each do |error|
          @error_msg << { msg: error, user: offer.user }
        end
      else
        # OfferSpaJob#perform takes (secondary_sale_id, offer_id, user_id); it used to be given
        # (offer_id, user_id), so every bulk "generate spa" raised ArgumentError
        OfferSpaJob.perform_now(offer.secondary_sale_id, offer.id, user_id)
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end

  def get_class
    Offer
  end
end
