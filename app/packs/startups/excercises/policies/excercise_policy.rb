class ExcercisePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      elsif user.has_cached_role?(:employee)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || (user.id == record.user_id)
  end

  def create?
    user.id == record.user_id && user.id == record.holding.user_id
    true
  end

  def new?
    true
  end

  def update?
    (create? || support?) && !record.approved
    true
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end

  def approve?
    user.has_cached_role?(:approver) && belongs_to_entity?(user, record)
  end
end
