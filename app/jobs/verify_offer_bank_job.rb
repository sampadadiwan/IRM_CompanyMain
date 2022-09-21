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
        check_details(response)
      else
        @offer.bank_verified = false
        @offer.bank_verification_status = "Account not found"
      end
    else
      @offer.bank_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    Rails.logger.debug response
    @offer.bank_verification_status = nil
    @offer.bank_verified = false
    @offer.bank_verification_response = response["result"]
  end

  def check_details(_response)
    name_at_bank = @offer.bank_verification_response["name_at_bank"].split
    Rails.logger.debug { "name_at_bank = #{name_at_bank}" }
    @offer.bank_verified = false

    given_names = [@offer.first_name.downcase, @offer.middle_name.downcase, @offer.last_name.downcase]

    name_at_bank.each do |name|
      Rails.logger.debug { "Matching #{name} with #{@offer.first_name} #{@offer.middle_name} #{@offer.last_name}" }
      @offer.bank_verified = true if given_names.include?(name.downcase)
    end

    @offer.bank_verification_status = "Name does not match" unless @offer.bank_verified
  end
end
