class EoiGenerateEsignJob < ApplicationJob
  queue_as :default

  # This is idempotent, we should be able to call it multiple times for the same ExpressionOfInterest
  def perform(expression_of_interest_id)
    Chewy.strategy(:sidekiq) do
      @expression_of_interest = ExpressionOfInterest.find(expression_of_interest_id)
      EoiEsignProvider.new(@expression_of_interest).trigger_signatures
    end
  end
end
