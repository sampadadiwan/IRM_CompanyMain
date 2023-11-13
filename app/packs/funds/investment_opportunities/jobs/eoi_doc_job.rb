class EoiDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same ExpressionOfInterest
  def perform(expression_of_interest_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      @expression_of_interest = ExpressionOfInterest.find(expression_of_interest_id)
      @investment_opportunity = @expression_of_interest.investment_opportunity
      @investor = @expression_of_interest.investor

      @templates = @investment_opportunity.documents.templates

      Rails.logger.debug { "Generating documents for #{@investor.investor_name}, for investment_opportunity #{@investment_opportunity.company_name}" }

      @expression_of_interest.investor_kycs.verified.each do |kyc|
        @templates.each do |investment_opportunity_doc_template|
          Rails.logger.debug { "Generating #{investment_opportunity_doc_template.name} for investment_opportunity #{@investment_opportunity.company_name}, for user #{kyc.full_name}" }

          # Delete any existing signed documents
          @expression_of_interest.documents.not_templates.where(name: investment_opportunity_doc_template.name).find_each(&:destroy)

          # Generate a new signed document
          send_notification("Generating #{investment_opportunity_doc_template.name} for investment_opportunity #{investment_opportunity.company_name}, for user #{kyc.full_name}", user_id, :info)

          EoiDocGenerator.new(@expression_of_interest, investment_opportunity_doc_template, user_id)
        rescue StandardError => e
          send_notification("Error generating #{investment_opportunity_doc_template.name} for investment_opportunity #{investment_opportunity.company_name}, for user #{kyc&.full_name}. #{e.message}", user_id, :danger)
        end
      end
    end

    nil
  end
end
