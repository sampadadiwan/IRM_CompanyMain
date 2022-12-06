class VerifyBankJob < ApplicationJob
  queue_as :default

  def perform(id); end

  private

  def verify
    if @model.bank_account_number && @model.ifsc_code
      response = KycVerify.new.verify_bank(@model.full_name, @model.bank_account_number, @model.ifsc_code)
      init_offer(response)

      if response["status"] == "completed"
        check_details(response)
      else
        @model.bank_verified = false
        @model.bank_verification_status = "Account not found"
      end
    else
      @model.bank_verification_status = "No Bank Account or IFSC Code Entered"
    end
  end

  def init_offer(response)
    Rails.logger.debug response
    @model.bank_verification_status = nil
    @model.bank_verified = false
    @model.bank_verification_response = response["result"]
  end

  def check_details(response)
    name_at_bank = @model.bank_verification_response["name_at_bank"].split
    Rails.logger.debug { "name_at_bank = #{name_at_bank}" }
    @model.bank_verified = false

    if response["fuzzy_match_result"] && response["fuzzy_match_score"] > 50
      @model.bank_verified = true
    else
      given_names = @model.full_name.downcase.split

      name_at_bank.each do |name|
        Rails.logger.debug { "Matching #{name} with #{@model.full_name}" }
        @model.bank_verified = true if given_names.include?(name.downcase)
      end
    end

    @model.bank_verification_status = "Name does not match" unless @model.bank_verified
  end
end
