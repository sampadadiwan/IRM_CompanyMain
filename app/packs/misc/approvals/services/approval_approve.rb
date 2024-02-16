class ApprovalApprove < ApprovalService
  step :approve
  step :notify

  def approve(_ctx, approval:, **)
    approval.approved = true
    approval.save
  end
end
