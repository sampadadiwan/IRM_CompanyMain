class OfferSpaJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  def perform(offer_id, user_id: nil)
    succeeded = false

    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      send_notification("Starting SPA generation for user #{offer.user}, Offer Id #{offer.id}", user_id, "info") if user_id.present?

      raise "No Offer Template found for Offer #{offer.id}" if offer.secondary_sale.documents.where(owner_tag: "Offer Template").blank?

      # In special cases there is a custom field in the offer, docs_to_generate, that specifies which documents to generate. This is to enable some offers to have only one doc generated, but others to have more than one doc. E.x if the shares are in DEMAT, then only SPA needs to be generated, if not then SPA and another doc needs to be generated.
      if offer.custom_fields.docs_to_generate.present?
        template_names = offer.custom_fields.docs_to_generate.split(",").map{|n| n.strip}
        templates = offer.secondary_sale.documents.where(owner_tag: "Offer Template").where(name: template_names)
        Rails.logger.debug { "OfferSpaJob: Generating only docs_to_generate #{template_names}" }
      else
        templates = offer.secondary_sale.documents.where(owner_tag: "Offer Template")
        Rails.logger.debug "OfferSpaJob: Generating all Offer Templates"
      end

      templates.find_each do |template|
        OfferSpaGenerator.new(offer, template)
        succeeded = true
      rescue StandardError => e
        send_notification("Error generating SPA for user #{offer.user}, Offer Id #{offer.id} - #{e.message}", user_id, "danger") if user_id.present?
        ExceptionNotifier.notify_exception(e)
        succeeded = false
      end

      send_notification("SPA generated for user #{offer.user}, Offer Id #{offer.id}", user_id, "success") if user_id.present?
      succeeded
    end
  end
end
