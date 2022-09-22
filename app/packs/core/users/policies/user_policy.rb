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
    user.id == record.id || user.entity_id == record.entity_id
  end

  def create?
    user.entity_id == record.entity_id
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    false
  end
end
