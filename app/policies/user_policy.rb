class UserPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role.to_sym == :holding
        scope.where(id: user.id)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def welcome?
    true
  end

  def show?
    user.has_cached_role?(:super) || user.id == record.id || user.entity_id == record.entity_id
  end

  def create?
    user.has_cached_role?(:super) || user.entity_id == record.entity_id
  end

  def new?
    user.has_cached_role?(:super) || user.entity_id == record.entity_id
  end

  def update?
    user.has_cached_role?(:super) || user.id == record.id
  end

  def edit?
    user.has_cached_role?(:super) || user.id == record.id
  end

  def destroy?
    false
  end
end
