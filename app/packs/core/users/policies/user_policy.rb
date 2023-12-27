class UserPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.curr_role.to_sym == :holding
        scope.where(id: user.id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end

    def resolve_admin
      scope.all
    end
  end

  def index?
    true
  end

  def welcome?
    true
  end

  def show?
    user.id == record.id || (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || super_user?
  end

  def create?
    (belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)) || super_user?
  end

  def new?
    user.has_cached_role?(:company_admin) || super_user?
  end

  def update?
    user.id == record.id ||
      create? || super_user?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end
end
