class ApprovalGenerateResponsesJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    Chewy.strategy(:active_job) do
      approval = Approval.find(approval_id)
      approval.generate_responses
    end
  end
end
