class VerifyPanJob < ApplicationJob
  queue_as :default

  def perform(obj_class:, obj_id:)
    Chewy.strategy(:sidekiq) do
      @model = obj_class.constantize.find(obj_id)
      @model = @model.decorate if @model.decorator_class?
      # remove when default decorator for kyc is fixed
      @model = InvestorKycVerificationDecorator.decorate(obj_class.constantize.find(obj_id)) if obj_class.ends_with?("Kyc")
      if @model.pan_verification_enabled?
        verify
        if %w[InvestorKyc IndividualKyc NonIndividualKyc].include?(obj_class)
          @model.save(validate: false)
        else
          @model.save
        end
      else
        Rails.logger.debug { "Skipping: pan_verification set to false for #{@model.entity.name}" }
      end
    end
  end

  private

  def verify
    if @model.pan_card
      response = KycVerify.new.verify_pan_card(@model.pan_card)
      init_offer(response)
      # api keeps returning verified as nil even on success
      verified = response[:verified] || (response[:status]&.casecmp?("success") && response[:name_matched])
      if verified
        @model.pan_verified = verified
        check_details(response)
      else
        @model.pan_verified = false
      end
    else
      @model.pan_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    logger.debug response
    if response[:status] == "success"
      @model.pan_verification_response = response&.to_h
      @model.pan_verification_status = ""
    else
      @model.pan_verification_status = "Failed to verify PAN card, please check PAN image"
      @model.pan_verification_response = response[:resp]&.parsed_response
    end
    @model.pan_verified = false
  end

  def check_details(response)
    id_number = response[:id_no].strip

    if id_number.strip != @model.PAN&.strip
      @model.pan_verification_status += " PAN number does not match"
      @model.pan_verified = false
    end

    if response[:name_matched] != true || response[:name]&.downcase != @model.full_name&.downcase
      @model.pan_verification_status += " Name does not match"
      @model.pan_verified = false
    end

    # dob format "dd/mm/yyyy"
    if response[:is_pan_dob_valid] != true || (@model.respond_to?(:birth_date) && response[:dob] != @model.birth_date&.strftime("%d/%m/%Y"))
      @model.pan_verification_status += " Date of birth does not match"
      @model.pan_verified = false
    end
  end
end
