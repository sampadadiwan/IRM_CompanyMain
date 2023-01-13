class OfferSpaJob < ApplicationJob
  queue_as :doc_gen

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      OfferSpaGenerator.new(offer)
    end
  end
end
