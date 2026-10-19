class ApprovalPolicy < ApprovalBasePolicy
  include WorkflowablePolicyMethods # journey?, assign_workflow?

  class Scope < BaseScope
    def resolve
      if user.curr_role == "investor"
        scope.for_investor(user)
      else
        super
      end
    end
  end

  def index?
    user.enable_approvals
  end

  def show?
    user.enable_approvals &&
      (permissioned_employee? || permissioned_investor?)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    user.enable_approvals &&
      permissioned_employee? && parent_in_users_firms?(record.owner)
  end

  # E: the fields anyone may send. approved, approved_count and rejected_count are not among them: an
  # approval is approved only through the Approve action, and the counts are tallied from the responses
  def permitted_attributes
    [:title, :agreements_reference, :entity_id, :response_status, :enable_approval_show_kycs, :due_date, :owner_id,
     :owner_type, :response_enabled_email, :form_type_id, { properties: {} }]
  end

  def new?
    create?
  end

  def update?
    create? && record.due_date >= Time.zone.today && !record.locked
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def approve?
    user.has_cached_role?(:approver) && update? && !record.approved
  end

  def close?
    update?
  end

  def send_reminder?
    update? && record.due_date >= Time.zone.today && record.approved
  end
end
