class OffersBulkActionJob < BulkActionJob
  def perform_action(offer, user_id, bulk_action, params: {})
    Rails.logger.info("Performing #{bulk_action} on Offer #{offer.id} - #{params}")
    msg = "#{bulk_action}: Offer #{offer.id}"
    send_notification(msg, user_id, :success)

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
        OfferSpaJob.perform_now(offer.id, user_id)
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
