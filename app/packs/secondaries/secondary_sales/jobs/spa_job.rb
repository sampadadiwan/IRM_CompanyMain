class SpaJob < ApplicationJob
  queue_as :default

  def perform(secondary_sale_id)
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
        rescue StandardError => e
          logger.error "Error creating offer SPA for offer id #{offer.id}"
          logger.error e.backtrace
          failed += 1
        end

        # cleanup
        File.delete(master_spa_path)
      else
        logger.debug "SpaJob: No master SPA uploaded. Not generating SPA"
      end

      logger.debug "SpaJob: succeeded #{succeeded}, failed #{failed}"
    end
  end
end
