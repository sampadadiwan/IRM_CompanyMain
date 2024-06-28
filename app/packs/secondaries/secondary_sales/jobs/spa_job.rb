class SpaJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id, user_id: nil)
    Chewy.strategy(:sidekiq) do
      # Counters
      succeeded = 0
      failed = 0

      # Find the sale
      secondary_sale = SecondarySale.find(secondary_sale_id)
      @error_msg = []
      # For each verified offer, generate the SPA
      secondary_sale.offers.verified.each do |offer|
        check_validity(offer)
        if OfferSpaJob.perform_now(offer.id, user_id:)
          succeeded += 1
        else
          failed += 1
        end
      rescue StandardError => e
        ExceptionNotifier.notify_exception(
          e,
          data: { message: "Error generating SPA for offer #{offer.id}" }
        )
        Rails.logger.error "Error generating SPA for user #{offer.user}, Offer Id #{offer.id} - #{e.message}"
        send_notification("SPA failed for user #{offer.user}, Offer Id #{offer.id}  - #{e.message}", user_id, "danger") if user_id.present?
        failed += 1
        @error_msg << { msg: e.message, user: offer.user }
      end

      logger.debug "SpaJob: succeeded #{succeeded}, failed #{failed}"

      msg = "SPA generation completed: succeeded #{succeeded}, failed #{failed}"
      msg += " Errors will be sent via email" if failed.positive? && user_id.present? && @error_msg.present?
      send_notification(msg, user_id, "success") if user_id.present?

      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: @error_msg).spa_job_errors.deliver_now if failed.positive? && user_id.present? && @error_msg.present?
    end
  end

  def check_validity(offer)
    raise "Offer #{offer.id} is not assiciated with any interest!" if offer.interest.blank?
    raise "No Offer Template found for Offer #{offer.id}" if offer.secondary_sale.documents.where(owner_tag: "Offer Template").blank?

    raise "Offer #{offer.id} does not have any Seller Signatories!" if offer.seller_signatories.blank?
    raise "Intrest #{offer.interest.id} for offer #{offer.id} does not have any Buyer Signatories!" if offer.buyer_signatories.blank?
  end
end
