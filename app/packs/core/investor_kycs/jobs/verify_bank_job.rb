class VerifyBankJob < ApplicationJob
  queue_as :default
  DELAY_SECONDS = 120

  KYC_CLASSES = %w[InvestorKyc IndividualKyc NonIndividualKyc].freeze

  def perform(obj_class:, obj_id:)
    # The record may have been deleted between enqueue and run - nothing to verify
    record = obj_class.constantize.find_by(id: obj_id)
    if record.nil?
      Rails.logger.info { "Skipping VerifyBankJob: #{obj_class} #{obj_id} no longer exists" }
      return
    end

    # M14 — KYCs get the strict name rule and the stale-result guard
    @kyc = KYC_CLASSES.include?(obj_class)

    Chewy.strategy(:sidekiq) do
      # remove when default decorator for kyc is fixed
      @model = if obj_class.ends_with?("Kyc")
                 InvestorKycVerificationDecorator.decorate(record)
               elsif record.decorator_class?
                 record.decorate
               else
                 record
               end
      if @model.bank_verification_enabled?
        # M14 D11 — the account / IFSC this check is about, taken before the (slow) provider call
        checked = checked_details(record)
        verify
        if @kyc
          save_if_still_current(record, checked)
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
    return unless response.body

    parsed = parsed_response(response)
    # X14 — a KYC stores the answer as a Hash: an answer that is not JSON (a gateway error page) is kept as it came,
    # inside one (assigning the bare String raised SerializationTypeMismatch, so the check failed with an error)
    parsed = { "unreadable_response" => parsed.to_s.first(2000) } if @kyc && !parsed.is_a?(Hash)
    @model.bank_verification_response = parsed
  end

  def parsed_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError => e
    # if response cannot be parsed, log the error and return nil as its shown on UI
    Rails.logger.error { "JSON::ParserError: #{e.message}" }
    response.body
  end

  def check_details(response)
    # M14 D10 — KYCs use the strict rule with a "review" outcome; offers and interests keep the old one (E55)
    return check_kyc_name if @kyc

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

  # M14 ⑤ H12–H14, E47–E52 — the provider's own name match, else BankNameMatch; a partial match is left for a person
  # ("Name needs review: the bank has '…'"), never rejected
  def check_kyc_name
    details = @model.bank_verification_response
    details = {} unless details.is_a?(Hash)
    bank_name = details["beneficiary_name_with_bank"].to_s
    outcome = BankNameMatch.call(kyc_name: @model.full_name, bank_name:,
                                 provider_match: [true, "true"].include?(details["fuzzy_match_result"]))
    @model.bank_verified = outcome == :match
    @model.bank_verification_status = "Name needs review: the bank has '#{bank_name}'" unless @model.bank_verified
  end

  # The account number and IFSC, as the guard compares them (spaces, case ignored)
  def checked_details(record)
    [BankDetailChangeGuard.normalised(record.bank_account_number), BankDetailChangeGuard.normalised(record.ifsc_code)]
  end

  # M14 D11, E53 — the provider call took seconds; apply its answer only if the KYC still has the account and IFSC it
  # checked. The row lock is taken after the HTTP call, so it is held only for the compare and the save.
  def save_if_still_current(record, checked)
    result = { bank_verified: @model.bank_verified, bank_verification_status: @model.bank_verification_status,
               bank_verification_response: @model.bank_verification_response }
    # X14 — say what happened when the answer could not be read
    unreadable = result[:bank_verification_response].is_a?(Hash) && result[:bank_verification_response].key?("unreadable_response")
    result[:bank_verification_status] = "The bank check's answer could not be read — run Bank verification again" if unreadable
    # A fresh copy of the row: the result was set on the one loaded before the call, which may now be out of date
    fresh = record.class.find(record.id)
    fresh.with_lock do
      current = checked_details(fresh)
      if current == checked
        fresh.assign_attributes(result)
        fresh.save(validate: false)
      else
        Rails.logger.info { "VerifyBankJob: stale result dropped for KYC #{fresh.id} (checked ending #{checked.first.last(4)}, now ending #{current.first.last(4)})" }
      end
    end
  end
end
