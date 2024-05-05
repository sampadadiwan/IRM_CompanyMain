class SpaJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id, user_id: nil)
    Chewy.strategy(:active_job) do
      # Counters
      succeeded = 0
      failed = 0

      # Find the sale
      secondary_sale = SecondarySale.find(secondary_sale_id)

      # For each verified offer, generate the SPA
      secondary_sale.offers.verified.each do |offer|
        if OfferSpaJob.perform_now(offer.id, user_id:)
          succeeded += 1
          send_notification("SPA generated for user #{offer.user}, Offer Id #{offer.id}", user_id, "success") if user_id.present?
        else
          failed += 1
          send_notification("SPA failed for user #{offer.user}, Offer Id #{offer.id}", user_id, "danger") if user_id.present?
        end
      rescue StandardError => e
        ExceptionNotifier.notify_exception(
          e,
          data: { message: "Error generating SPA for offer #{offer.id}" }
        )
        failed += 1
        send_notification("SPA failed for user #{offer.user}, Offer Id #{offer.id}", user_id, "danger") if user_id.present?
      end

      logger.debug "SpaJob: succeeded #{succeeded}, failed #{failed}"
      send_notification("SPA generated succeeded #{succeeded}, failed #{failed}", user_id, "success") if user_id.present?
    end
  end
end
