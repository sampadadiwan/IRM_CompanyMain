class OfferSpaJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  def perform(offer_id, user_id: nil)
    succeeded = false

    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      send_notification("Starting SPA generation for user #{offer.user}, Offer Id #{offer.id}", user_id, "info") if user_id.present?
      offer.secondary_sale.documents.where(owner_tag: "Offer Template").find_each do |template|
        OfferSpaGenerator.new(offer, template)
        succeeded = true
      rescue StandardError
        succeeded = false
      end

      send_notification("SPA generated for user #{offer.user}, Offer Id #{offer.id}", user_id, "success") if user_id.present?
      succeeded
    end
  end
end
