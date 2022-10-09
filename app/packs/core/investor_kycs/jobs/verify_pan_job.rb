class VerifyPanJob < ApplicationJob
  queue_as :default

  def perform(id); end

  private

  def verify
    if @model.pan_card
      response = KycVerify.new.verify_pan_card(@model.pan_card.url(expires_in: 60 * 3))
      init_offer(response)

      if response["status"] == "completed"
        @model.pan_verified = true
        @model.pan_verification_response = response["result"]
        check_details(response)

      else
        @model.pan_verified = false
        @model.pan_verification_status = response["message"]
      end
    else
      @model.pan_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    logger.debug response
    @model.pan_verification_response = nil
    @model.pan_verification_status = nil
    @model.pan_verified = false
  end

  def check_details(response)
    name_on_card = @model.pan_verification_response["extraction_output"]["name_on_card"]
    pan_type = @model.pan_verification_response["extraction_output"]["pan_type"]
    id_number = @model.pan_verification_response["extraction_output"]["id_number"]

    @model.pan_verification_status = response["message"].presence || ""

    if id_number.strip != @model.PAN.strip
      @model.pan_verification_status += " PAN number does not match"
      @model.pan_verified = false
    end

    if pan_type.strip != "Individual"
      @model.pan_verification_status += " PAN is not for Individual"
      @model.pan_verified = false
    end

    if name_on_card.strip != "#{@model.first_name} #{@model.middle_name} #{@model.last_name}" &&
       name_on_card.strip != "#{@model.last_name} #{@model.middle_name} #{@model.first_name}"
      @model.pan_verification_status += " Name does not match"
      @model.pan_verified = false
    end
  end
end
