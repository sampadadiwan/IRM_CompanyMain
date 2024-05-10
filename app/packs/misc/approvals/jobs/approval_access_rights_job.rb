class ApprovalAccessRightsJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    Chewy.strategy(:sidekiq) do
      approval = Approval.find(approval_id)
      approval.setup_owner_access_rights
    end
  end
end
