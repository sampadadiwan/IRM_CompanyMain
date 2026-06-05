class IncomingEmailPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.has_cached_role?(:company_admin) || super_user?
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    true
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record)
  end

  def edit?
    update?
  end

  def destroy?
    update? || support?
  end
end
