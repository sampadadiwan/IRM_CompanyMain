class ApprovalGenerateResponsesJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    Chewy.strategy(:sidekiq) do
      approval = Approval.find(approval_id)
      approval.generate_responses
    end
  end
end
