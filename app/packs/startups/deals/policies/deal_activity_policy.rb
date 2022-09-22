class DealActivityPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where("entity_id=?", user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    if user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
      true
    else
      record.deal_investor && record.deal_investor.investor_entity_id == user.entity_id
    end
  end

  def create?
    user.has_cached_role?(:super) || (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
