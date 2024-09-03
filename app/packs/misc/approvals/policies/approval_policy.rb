class ApprovalPolicy < ApprovalBasePolicy
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
    user.enable_approvals &&
      permissioned_employee?
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
