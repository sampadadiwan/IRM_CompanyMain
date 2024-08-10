class CapitalRemittanceDocJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalRemittance
  def perform(capital_remittance_id, user_id = nil)
    error_msg = []
    Chewy.strategy(:sidekiq) do
      @capital_remittance = CapitalRemittance.find(capital_remittance_id)
      @capital_commitment = @capital_remittance.capital_commitment
      @investor_kyc = @capital_commitment.investor_kyc
      @fund = @capital_remittance.fund

      if kyc_ok?(user_id, error_msg)
        # Try and get the template from the capital_commitment
        @templates = @capital_remittance.capital_commitment.templates("Call Template")

        msg = "Generating Remittance documents for #{@capital_commitment.investor_name}, for fund #{@fund.name} and kyc #{@investor_kyc.id}"
        send_notification(msg, user_id, :info)
        Rails.logger.debug { msg }

        @templates.each do |fund_doc_template|
          Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@capital_remittance.investor_name}" }
          # Delete any existing signed documents
          @capital_remittance.documents.not_templates.where(name: fund_doc_template.name).find_each(&:destroy)
          # Generate a new signed document
          CapitalRemittanceDocGenerator.new(@capital_remittance, fund_doc_template, user_id)
        rescue Exception => e
          msg = "Error generating template #{fund_doc_template.name} for fund #{@capital_remittance.folio_id}, for #{@capital_commitment.investor_name}: #{e.message}"
          handle_error(msg, fund_doc_template, @capital_commitment, @investor_kyc, user_id, error_msg)
        end

        handle_error("No Call templates found for #{@capital_remittance}", nil, @capital_commitment, @investor_kyc, user_id, error_msg) if @templates.blank?

      end
    end

    error_msg
  end

  def kyc_ok?(user_id, error_msg)
    if @investor_kyc.blank? || !@investor_kyc.verified
      msg = "Investor KYC not verified for #{@capital_remittance.investor_name}. Skipping."
      handle_error(msg, nil, @capital_commitment, @investor_kyc, user_id, error_msg)
      false
    else
      true
    end
  end

  def handle_error(msg, fund_doc_template, capital_commitment, _investor_kyc, user_id, error_msg)
    Rails.logger.error { msg }
    send_notification(msg, user_id, :danger)

    error_msg << { msg:, template: fund_doc_template&.name, folio_id: capital_commitment.folio_id, investor_name: capital_commitment.to_s }
    # Sleep so user can see this error before the next doc is tried
    sleep(2)
  end
end
