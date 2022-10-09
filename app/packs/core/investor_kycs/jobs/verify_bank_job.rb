class VerifyBankJob < ApplicationJob
  queue_as :default

  def perform(id); end

  private

  def verify
    if @model.bank_account_number && @model.ifsc_code
      response = KycVerify.new.verify_bank(@model.bank_account_number, @model.ifsc_code)
      init_offer(response)

      if response["status"] == "completed"
        check_details(response)
      else
        @model.bank_verified = false
        @model.bank_verification_status = "Account not found"
      end
    else
      @model.bank_verification_status = "No PAN card uploaded"
    end
  end

  def init_offer(response)
    Rails.logger.debug response
    @model.bank_verification_status = nil
    @model.bank_verified = false
    @model.bank_verification_response = response["result"]
  end

  def check_details(_response)
    name_at_bank = @model.bank_verification_response["name_at_bank"].split
    Rails.logger.debug { "name_at_bank = #{name_at_bank}" }
    @model.bank_verified = false

    given_names = [@model.first_name.downcase, @model.middle_name.downcase, @model.last_name.downcase]

    name_at_bank.each do |name|
      Rails.logger.debug { "Matching #{name} with #{@model.first_name} #{@model.middle_name} #{@model.last_name}" }
      @model.bank_verified = true if given_names.include?(name.downcase)
    end

    @model.bank_verification_status = "Name does not match" unless @model.bank_verified
  end
end
