class SpaJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id, user_id: nil)
    Chewy.strategy(:sidekiq) do
      # Counters
      succeeded = 0
      failed = 0

      # Find the sale
      secondary_sale = SecondarySale.find(secondary_sale_id)

      if secondary_sale.spa
        # Downlad the SPA from the sale
        file = secondary_sale.spa.download
        sleep(2)
        master_spa_path = file.path
        # For each verified offer, generate the SPA
        secondary_sale.offers.verified.each do |offer|
          OfferSpaGenerator.new(offer, master_spa_path)
          succeeded += 1
          send_notification("SPA generated for user #{offer.user}, Offer Id #{offer.id}", user_id, "success") if user_id.present?
        rescue StandardError => e
          logger.error "Error creating offer SPA for offer id #{offer.id}"
          logger.error e.backtrace
          ExceptionNotifier.notify_exception(
            e,
            data: { message: "Error generating SPA for offer #{offer.id}" }
          )
          failed += 1
          send_notification("SPA failed for user #{offer.user}, Offer Id #{offer.id}", user_id, "danger") if user_id.present?
        end

        # cleanup
        File.delete(master_spa_path)
      else
        logger.debug "SpaJob: No master SPA uploaded. Not generating SPA"
      end

      logger.debug "SpaJob: succeeded #{succeeded}, failed #{failed}"
      send_notification("SPA generated succeeded #{succeeded}, failed #{failed}", user_id, "success") if user_id.present?
    end
  end
end
