class EoiDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same ExpressionOfInterest
  def perform(expression_of_interest_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      @expression_of_interest = ExpressionOfInterest.find(expression_of_interest_id)
      @investment_opportunity = @expression_of_interest.investment_opportunity
      @investor = @expression_of_interest.investor
      @templates = @investment_opportunity.documents.where(owner_tag: "Template")

      Rails.logger.debug { "Generating documents for #{@investor.investor_name}, for investment_opportunity #{@investment_opportunity.company_name}" }

      # Ensure that any prev esigns are deleted for this capital comittment
      EoiEsignProvider.new(@expression_of_interest).cleanup_prev

      @expression_of_interest.investor_kycs.verified.each do |kyc|
        @templates.each do |investment_opportunity_doc_template|
          Rails.logger.debug { "Generating #{investment_opportunity_doc_template.name} for investment_opportunity #{@investment_opportunity.company_name}, for user #{kyc.full_name}" }
          # Delete any existing signed documents
          @expression_of_interest.documents.where(name: investment_opportunity_doc_template.name).each(&:destroy)
          # Generate a new signed document
          EoiDocGenerator.new(@expression_of_interest, investment_opportunity_doc_template, user_id)
        end
      end
    end

    nil
  end
end
