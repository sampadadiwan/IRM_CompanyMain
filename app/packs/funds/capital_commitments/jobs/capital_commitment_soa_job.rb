class CapitalCommitmentSoaJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

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
        msg = "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@investor_kyc&.full_name}"
        Rails.logger.debug { msg }
        # Notify started
        send_notification(msg, user_id, :info)
        # Generate a new signed document
        SoaGenerator.new(@capital_commitment, fund_doc_template, start_date, end_date, user_id)
        # Notify completed
        send_notification(msg.gsub("Generating", "Generated"), user_id, :success)
      rescue Exception => e
        send_notification("Error generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@investor_kyc&.full_name}. #{e.message}", user_id, :danger)
        ExceptionNotifier.notify_exception(e, data: { capital_commitment_id:, start_date:, end_date:, user_id:, template_name: })
        raise e
      end
    end

    nil
  end
end
