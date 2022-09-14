class ApprovalPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      Approval.for_investor(user).where(id: record.id).present?
  end

  def create?
    (user.entity_id == record.entity_id) &&
      (user.has_cached_role?(:startup) || user.has_cached_role?(:fund_manager))
  end

  def new?
    create?
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
    update? && !record.approved && record.access_rights.count.positive?
  end

  def send_reminder?
    update? && record.approved
  end
end
