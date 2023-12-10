class CapitalRemittanceDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalRemittance
  def perform(capital_remittance_id, user_id = nil)
    error_msg = []
    Chewy.strategy(:sidekiq) do
      @capital_remittance = CapitalRemittance.find(capital_remittance_id)
      @capital_commitment = @capital_remittance.capital_commitment
      @fund = @capital_remittance.fund
      @investor = @capital_remittance.investor

      if @capital_commitment.investor_kyc.blank? || !@capital_commitment.investor_kyc.verified
        msg = "Investor KYC not verified for #{@capital_remittance.investor_name}. Skipping..."
        send_notification(msg, user_id, :danger)
        Rails.logger.error { msg }
        sleep(2)
      else
        # Try and get the template from the capital_commitment
        @templates = @capital_remittance.capital_commitment.templates("Call Template")
        
        msg = "Generating Remittance documents for #{@investor.investor_name}, for fund #{@fund.name}"
        send_notification(msg, user_id, :info)
        Rails.logger.debug { msg }

        @templates.each do |fund_doc_template|
          Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@capital_remittance.investor_name}" }
          # Delete any existing signed documents
          @capital_remittance.documents.not_templates.where(name: fund_doc_template.name).find_each(&:destroy)
          # Generate a new signed document
          CapitalRemittanceDocGenerator.new(@capital_remittance, fund_doc_template, user_id)
        rescue StandardError => e
          msg = "Error generating #{fund_doc_template.name} for fund #{capital_remittance.fund.name}, for #
          {investor_kyc.full_name} #{e.message}"

          send_notification(msg, user_id, "danger")
          Rails.logger.error { msg }

          error_msg << "Faled for {investor_kyc.full_name} #{e.message}"

          # Sleep so user can see this error before the next doc is tried
          sleep(2)
        end
      end
    end

    # Notify on all errors
    send_notification(error_msg.join(", "), user_id, :danger) if error_msg.present?
  end
end
