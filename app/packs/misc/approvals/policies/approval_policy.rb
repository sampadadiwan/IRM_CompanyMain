class ApprovalPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) ||
      Approval.for_investor(user).where(id: record.id).present?
  end

  def create?
    belongs_to_entity?(user, record) &&
      (user.curr_role = "company_admin")
  end

  def new?
    (user.curr_role = "company_admin")
  end

  def update?
    create? && record.due_date >= Time.zone.today
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
    update? && record.approved
  end
end
