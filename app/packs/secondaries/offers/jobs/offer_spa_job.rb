class OfferSpaJob < ApplicationJob
  queue_as :doc_gen

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      offer.secondary_sale.documents.where(owner_tag: "Seller Template").each do |template|
        OfferSpaGenerator.new(offer, template)
      end
    end
  end
end
