class CapitalRemittanceDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalRemittance
  def perform(capital_remittance_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      @capital_remittance = CapitalRemittance.find(capital_remittance_id)
      @fund = @capital_remittance.fund
      @investor = @capital_remittance.investor

      # Try and get the template from the capital_commitment
      @templates = @capital_remittance.capital_commitment.templates("Call Template")

      Rails.logger.debug { "Generating Remittance documents for #{@investor.investor_name}, for fund #{@fund.name}" }

      @templates.each do |fund_doc_template|
        Rails.logger.debug { "Generating #{fund_doc_template.name} for fund #{@fund.name}, for user #{@capital_remittance.investor_name}" }
        # Delete any existing signed documents
        @capital_remittance.documents.where(name: fund_doc_template.name).each(&:destroy)
        # Generate a new signed document
        CapitalRemittanceDocGenerator.new(@capital_remittance, fund_doc_template, user_id)
      end
    end

    nil
  end
end
