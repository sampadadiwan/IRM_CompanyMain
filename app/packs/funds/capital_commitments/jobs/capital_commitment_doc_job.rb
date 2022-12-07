class CapitalCommitmentDocJob < ApplicationJob
  queue_as :default

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(capital_commitment_id)
    Chewy.strategy(:sidekiq) do
      @capital_commitment = CapitalCommitment.find(capital_commitment_id)
      @fund = @capital_commitment.fund
      @investor = @capital_commitment.investor
      @templates = @fund.documents.where(owner_tag: "Template")

      Rails.logger.debug { "Generating documents for #{@investor.investor_name}, for fund #{@fund.name}" }

      @capital_commitment.investor_kycs.verified.each do |kyc|
        @templates.each do |fund_doc_template|
          Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{kyc.user.full_name}" }
          # Delete any existing signed documents
          @capital_commitment.documents.where(signed_by_id: kyc.user.id, name: fund_doc_template.name).each(&:destroy)
          # Generate a new signed document
          CapitalCommitmentDocGenerator.new(@capital_commitment, fund_doc_template, kyc.user)
        end
      end
    end

    nil
  end
end
