class VerifyBankJob < ApplicationJob
  queue_as :default

  def perform(obj_class:, obj_id:)
    Chewy.strategy(:sidekiq) do
      @model = obj_class.constantize.find(obj_id)
      @model = @model.decorate if @model.decorator_class?
      if @model.bank_verification_enabled?
        verify
        if %w[InvestorKyc IndividualKyc NonIndividualKyc].include?(obj_class)
          @model.save(validate: false)
        else
          @model.save
        end
      else
        Rails.logger.debug { "Skipping: bank_verification set to false for #{@model.entity.name}" }
      end
    end
  end

  private

  def verify
    if @model.bank_account_number && @model.ifsc_code
      response = KycVerify.new.verify_bank(@model.full_name, @model.bank_account_number, @model.ifsc_code)
      init_offer(response)

      if response["verified"]
        check_details(response)
      else
        @model.bank_verified = false
        @model.bank_verification_status = response["error_msg"]
      end
    else
      @model.bank_verification_status = "No Bank Account Number / IFSC Code Entered"
    end
  end

  # {"id":"E2YKNGCI4LFPHM6","verified":true,"verified_at":"2022-12-11 18:27:39","beneficiary_name_with_bank":"THIMMAIAH C","fuzzy_match_result":true,"fuzzy_match_score":88}
  def init_offer(response)
    Rails.logger.debug response
    @model.bank_verification_status = nil
    @model.bank_verified = false
    @model.bank_verification_response = parsed_response(response) if response.body
  end

  def parsed_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    # if response cannot be parsed, log the error and return nil as its shown on UI
    Rails.logger.error { "JSON::ParserError: #{e.message}" }
    response.body
  end

  def check_details(response)
    name_at_bank = @model.bank_verification_response["beneficiary_name_with_bank"].split
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
