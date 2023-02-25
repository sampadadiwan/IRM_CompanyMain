class ExcercisePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:employee)
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
    (user.entity_id == record.entity_id) || user.id == record.user_id
  end

  def create?
    (user.id == record.user_id && user.id == record.holding.user_id)
  end

  def new?
    create?
  end

  def update?
    create? && !record.approved
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end

  def approve?
    user.has_cached_role?(:approver) && user.entity_id == record.entity_id
  end
end
