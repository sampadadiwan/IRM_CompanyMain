class FundPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:fund_manager) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:fund_manager)
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    user.enable_funds
  end

  def show?
    user.enable_funds &&
      (
        permissioned_employee? ||
        permissioned_investor?
      )
  end

  def timeline?
    update?
  end

  def create?
    (user.entity_id == record.entity_id) && user.enable_funds
  end

  def new?
    user.has_cached_role?(:company_admin)
  end

  def update?
    permissioned_employee?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
