class CapitalCommitmentSoaJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(capital_commitment_id, start_date, end_date, user_id: nil, template_name: nil)
    Chewy.strategy(:sidekiq) do
      @capital_commitment = CapitalCommitment.find(capital_commitment_id)
      @fund = @capital_commitment.fund
      @investor = @capital_commitment.investor
      @investor_kyc = @capital_commitment.investor_kyc

      # Try and get the template from the capital_commitment
      @templates = @capital_commitment.templates("SOA Template", template_name)

      Rails.logger.debug { "Generating documents for #{@investor.investor_name}, for fund #{@fund.name}" }

      @templates.each do |fund_doc_template|
        Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@investor_kyc&.full_name}" }
        send_notification("Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@investor_kyc&.full_name}", :info)
        # Generate a new signed document
        SoaGenerator.new(@capital_commitment, fund_doc_template, start_date, end_date, user_id)
      rescue StandardError
        send_notification("Error generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@investor_kyc&.full_name}")
      end
    end

    nil
  end
end
