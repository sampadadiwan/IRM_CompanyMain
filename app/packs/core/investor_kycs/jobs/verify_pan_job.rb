class VerifyPanJob < ApplicationJob
  queue_as :default

  def perform(id); end

  private

  def verify
    if @model.pan_card
      response = KycVerify.new.verify_pan_card(@model.pan_card)
      init_offer(response)

      if response[:status] == "success" && response[:verified]
        @model.pan_verified = response[:verified]
        @model.pan_verification_response = response
        check_details(response)
      else
        @model.pan_verified = false
        @model.pan_verification_status = response[:status]
      end
    else
      @model.pan_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    logger.debug response
    @model.pan_verification_response = nil
    @model.pan_verification_status = ""
    @model.pan_verified = false
  end

  def check_details(response)
    id_number = response[:id_no].strip

    if id_number.strip != @model.PAN.strip
      @model.pan_verification_status += " PAN number does not match"
      @model.pan_verified = false
    end

    if response[:name_matched] != true || response[:name]&.downcase != @model.full_name&.downcase
      @model.pan_verification_status += " Name does not match"
      @model.pan_verified = false
    end
  end
end
