class ApprovalClose < ApprovalService
  step :close
  step :owner_post_approval

  def close(_ctx, approval:, **)
    approval.locked = true
    approval.save
  end

  def owner_post_approval(_ctx, approval:, **)
    if approval.owner
      # This is where the owner of the approval can do something after the approval is closed
      # Typically extracts data from the approval responses to update the owner
      # Ex. Funds can extract the approved amount and add it to the commitment capturing the approved amount for a PI
      approval.owner.post_approval(approval)
    else
      true
    end
  end
end
