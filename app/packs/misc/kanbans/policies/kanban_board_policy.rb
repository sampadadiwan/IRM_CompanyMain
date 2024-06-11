class KanbanBoardPolicy < ApplicationPolicy
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
    %w[employee].include?(user.curr_role)
  end

  def show?
    (permissioned_employee? || "#{record.owner_type}Policy".constantize.new(user, record.owner).show?) && user.enable_kanban
  end

  def create?
    show?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create? && @record.self_owned?
  end

  def destroy?
    %w[employee].include?(user.curr_role) && user.has_cached_role?(:company_admin)
  end

  def archived_kanban_columns?
    show?
  end

  def permissioned_employee?
    if belongs_to_entity?(user, record)
      if user.has_cached_role?(:company_admin)
        true
      else
        %w[employee].include?(user.curr_role)
      end
    else
      false
    end
  end
end
