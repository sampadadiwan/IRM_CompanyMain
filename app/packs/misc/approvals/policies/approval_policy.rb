class ApprovalPolicy < ApplicationPolicy
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
    user.entity.permissions.enable_approvals?
  end

  def show?
    (user.entity.permissions.enable_approvals? &&
      (belongs_to_entity?(user, record) ||
        Approval.for_investor(user).where(id: record.id).present?)) || support?
  end

  def create?
    (user.entity.permissions.enable_approvals? &&
      belongs_to_entity?(user, record) &&
      user.has_cached_role?("company_admin")) || support?
  end

  def new?
    user.entity.permissions.enable_approvals? && user.has_cached_role?("company_admin")
  end

  def update?
    (create? && record.due_date >= Time.zone.today && !record.locked) || support?
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

  def send_reminder?
    create? && record.due_date >= Time.zone.today && record.approved
  end
end
