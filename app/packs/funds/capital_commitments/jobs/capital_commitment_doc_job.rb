class CapitalCommitmentDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(capital_commitment_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      @capital_commitment = CapitalCommitment.find(capital_commitment_id)
      @fund = @capital_commitment.fund
      @investor = @capital_commitment.investor

      @templates = @capital_commitment.templates("Commitment Template")

      if @templates.present?
        Rails.logger.debug { "Generating documents for #{@investor.investor_name}, for fund #{@fund.name}" }

        # Ensure that any prev esigns are deleted for this capital comittment
        CapitalCommitmentEsignProvider.new(@capital_commitment).cleanup_prev

        @templates.each do |fund_doc_template|
          Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@capital_commitment.investor_kyc.full_name}" }
          # Delete any existing signed documents
          @capital_commitment.documents.where(name: fund_doc_template.name).each(&:destroy)
          # Generate a new signed document
          CapitalCommitmentDocGenerator.new(@capital_commitment, fund_doc_template, user_id)
        end
      else
        Rails.logger.debug { "Not generating documents for #{@investor.investor_name}, for fund #{@fund.name}, no templates found" }
      end
    end
    nil
  end
end
