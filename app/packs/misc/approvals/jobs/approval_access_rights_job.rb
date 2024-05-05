class ApprovalAccessRightsJob < ApplicationJob
  queue_as :default

  def perform(approval_id)
    Chewy.strategy(:active_job) do
      approval = Approval.find(approval_id)
      approval.setup_owner_access_rights
    end
  end
end
