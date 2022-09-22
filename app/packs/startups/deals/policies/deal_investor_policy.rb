class DealInvestorPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:startup)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:investor)
        DealInvestor.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    user.has_cached_role?(:super) ||
      (user.entity_id == record.entity_id) ||
      (user.entity_id == record.investor_entity_id)
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
