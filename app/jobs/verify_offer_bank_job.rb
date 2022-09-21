class VerifyOfferBankJob < ApplicationJob
  queue_as :default

  def perform(offer_id)
    Chewy.strategy(:sidekiq) do
      @offer = Offer.find(offer_id)
      verify
      @offer.save
    end
  end

  private

  def verify
    if @offer.bank_account_number && @offer.ifsc_code
      response = KycVerify.new.verify_bank(@offer.bank_account_number, @offer.ifsc_code)
      init_offer(response)

      if response["status"] == "completed"
        @offer.bank_verified = true
      else
        @offer.bank_verified = false
        @offer.bank_verification_status = response["message"]
      end
    else
      @offer.bank_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    Rails.logger.debug response
    @offer.bank_verification_response = nil
    @offer.bank_verification_status = nil
    @offer.bank_verified = false
    @offer.bank_verification_response = response["result"]
  end
end
