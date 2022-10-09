class VerifyOfferPanJob < VerifyPanJob
  queue_as :default

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      @model = Offer.find(offer_id)
      verify
      @model.save
    end
  end
end
