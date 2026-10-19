class KanbanCardPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %w[employee].include?(user.curr_role) # && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.none
      end
    end
  end

  def index?
    permissioned_employee? && user.enable_kanban
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    permissioned_employee? && user.enable_kanban && parent_in_users_firms?(record.kanban_board)
  end

  def new?
    create?
  end

  def show?
    index?
  end

  def update?
    create?
  end

  def destroy?
    create?
  end

  def move_kanban_card?
    update?
  end

  def update_sequence?
    update?
  end

  def permissioned_employee?
    if belongs_to_entity?(user, record)
      user.has_cached_role?(:company_admin) || %w[employee].include?(user.curr_role)
    else
      false
    end
  end
end
