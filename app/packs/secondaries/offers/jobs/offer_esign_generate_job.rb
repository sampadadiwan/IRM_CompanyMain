class OfferEsignGenerateJob < ApplicationJob
  queue_as :default

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      offer = Offer.find(offer_id)
      OfferEsignProvider.new(offer).trigger_signatures
    end
  end
end
