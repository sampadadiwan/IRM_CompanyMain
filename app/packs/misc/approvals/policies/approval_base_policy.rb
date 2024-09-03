class ApprovalBasePolicy < ApplicationPolicy
  def permissioned_employee?(perm = nil)
    approval_id = record.instance_of?(Approval) ? record.id : record.approval_id
    super(approval_id, "Approval", perm)
  end
end
