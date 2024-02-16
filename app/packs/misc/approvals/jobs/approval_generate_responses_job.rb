class ApprovalGenerateResponsesJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    approval = Approval.find(approval_id)
    approval.generate_responses
  end
end
