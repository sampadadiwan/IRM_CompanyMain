class OfferSpaJob < ApplicationJob
  queue_as :default

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      OfferSpaGenerator.new(offer)
    end
  end
end
