# Side letters are GP-internal legal records: entity-scoped, admin-managed.
class SideLetterPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee) || user.support?
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee) || user.support?
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end

  def create?
    user.has_cached_role?(:company_admin) && belongs_to_entity?(user, record)
  end

  def new?
    user.has_cached_role?(:company_admin)
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end
end
