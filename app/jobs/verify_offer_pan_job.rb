class VerifyOfferPanJob < ApplicationJob
  queue_as :default

  def perform(offer_id)
    @offer = Offer.find(offer_id)

    if @offer.pan_card
      response = KycVerify.new.verify_pan_card(@offer.pan_card.url(expires_in: 60))
      if response["status"] == "completed"
        @offer.pan_verified = true
        @offer.pan_verification_response = response["result"]
        check_details(response)

      else
        @offer.pan_verified = false
        @offer.pan_verification_status = response["message"]
      end
    else
      @offer.pan_verification_status = "No PAN card uploaded"
    end

    @offer.save
  end

  def check_details(response)
    name_on_card = @offer.pan_verification_response["extraction_output"]["name_on_card"]
    pan_type = @offer.pan_verification_response["extraction_output"]["pan_type"]
    id_number = @offer.pan_verification_response["extraction_output"]["id_number"]

    @offer.pan_verification_status = response["message"].presence || ""

    if id_number.strip != @offer.PAN.strip
      @offer.pan_verification_status += " PAN number does not match"
      @offer.pan_verified = false
    end

    if pan_type.strip != "Individual"
      @offer.pan_verification_status += " PAN is not for Individual"
      @offer.pan_verified = false
    end

    if name_on_card.strip != "#{@offer.first_name} #{@offer.middle_name} #{@offer.last_name}" &&
       name_on_card.strip != "#{@offer.last_name} #{@offer.middle_name} #{@offer.first_name}"
      @offer.pan_verification_status += " Name does not match"
      @offer.pan_verified = false
    end
  end
end
