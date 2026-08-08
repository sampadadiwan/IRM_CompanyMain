class TaskPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.support?
        # Support user
        scope.where("entity_id=? or for_entity_id=?", user.entity_id, user.entity_id)
      elsif user.has_cached_role?(:company_admin) || user.curr_role == "investor"
        # Show tasks which are not for support only
        scope.where("entity_id=? or for_entity_id=?", user.entity_id, user.entity_id).not_for_support
      elsif user.has_cached_role?(:employee)
        # Employees can see tasks assigned to them OR tasks for deals they have access to
        # For simplicity in this feature, we allow seeing all deal tasks for their entity
        scope.where("entity_id=?", user.entity_id).where(owner_type: %w[Deal DealInvestor]).or(
          scope.where("assigned_to_id=?", user.id)
        ).not_for_support
      else
        scope.none
      end
    end
  end

  def index?
    !user.investor_advisor?
  end

  def deal_tasks?
    index?
  end

  def show?
    if support?
      create?
    else
      create? && record.for_support == false
    end
  end

  def create?
    return true if support?
    return false unless belongs_to_entity?(user, record)
    return true if user.has_cached_role?(:company_admin)
    return true if crud?(user, record, :create)
    return true if record.owner.blank? && user.has_cached_role?(:employee)
    return true if record.owner.blank? # Allow creation when owner not yet set

    owner_policy.update?
  end

  def new?
    create?
  end

  def update?
    create? # || (record.owner && Pundit.policy(user, record.owner).show?)
  end

  def completed?
    update?
  end

  # Kanban board drag & drop — same rights as completing/editing a task
  def update_status?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def destroy_series?
    destroy?
  end
end
