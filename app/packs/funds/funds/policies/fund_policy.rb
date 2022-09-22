class FundPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:fund_manager)
        scope.where(entity_id: user.entity_id)
      else
        Fund.for_investor(user)
      end
    end
  end

  def index?
    user.entity.enable_funds
  end

  def show?
    user.entity.enable_funds &&
      (
        (user.entity_id == record.entity_id) ||
        Fund.for_investor(user).where("funds.id=?", record.id)
      )
  end

  def timeline?
    update?
  end

  def create?
    (user.entity_id == record.entity_id) && user.entity.enable_funds
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
    update?
  end
end
