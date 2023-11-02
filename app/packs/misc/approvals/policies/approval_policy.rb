class ApprovalPolicy < ApplicationPolicy
  def index?
    user.entity.enable_approvals
  end

  def show?
    (user.entity.enable_approvals &&
      (belongs_to_entity?(user, record) ||
        Approval.for_investor(user).where(id: record.id).present?)) || super_user?
  end

  def create?
    (user.entity.enable_approvals &&
      belongs_to_entity?(user, record) &&
      (user.curr_role = "company_admin")) || super_user?
  end

  def new?
    user.entity.enable_approvals && (user.curr_role = "company_admin")
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
    user.has_cached_role?(:approver) && update? && !record.approved && record.access_rights.count.positive?
  end

  def send_reminder?
    create? && record.due_date >= Time.zone.today && record.approved
  end
end
