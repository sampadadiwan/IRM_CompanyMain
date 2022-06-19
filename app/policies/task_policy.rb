class TaskPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id).or(scope.where("investors.investor_entity_id=?", user.entity_id)).joins(:investor)
      end
    end
  end

  def index?
    true
  end

  def show?
    create?
  end

  def create?
    if user.entity_id == record.entity_id
      true
    else
      record.investor && record.investor.investor_entity_id == user.entity_id
    end
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def completed?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
