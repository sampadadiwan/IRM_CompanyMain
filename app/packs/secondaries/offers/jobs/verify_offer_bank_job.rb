class VerifyOfferBankJob < VerifyBankJob
  queue_as :default

  def perform(offer_id)
    Chewy.strategy(:atomic) do
      @model = Offer.find(offer_id)
      verify
      @model.save
    end
  end
end
