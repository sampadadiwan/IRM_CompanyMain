class ApprovalCreate < ApprovalService
  step :create_model
  left :handle_errors, fail_fast: true
  step :setup_owner_access_rights
  step :generate_responses
  step :notify

  def create_model(_ctx, approval:, **)
    approval.save
  end

  def setup_owner_access_rights(_ctx, approval:, **)
    if approval.owner.present?
      approval.owner.access_rights.each do |ar|
        new_ar = ar.dup
        new_ar.entity_id = approval.entity_id
        new_ar.owner = approval
        new_ar.save
      end
    else
      Rails.logger.debug "No access rights to setup"
    end
    true
  end

  def generate_responses(_ctx, approval:, **)
    ApprovalGenerateResponsesJob.perform_later(approval.id)
    true
  end
end
