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

  def permissioned_employee?
    user.entity_id == record.entity_id &&
      Fund.for_employee(user).where("funds.id=?", record.id).present?
  end

  def show?
    user.enable_funds &&
      (
        (user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)) ||
        permissioned_employee? ||
        (!user.has_cached_role?(:fund_manager) && Fund.for_investor(user).where("funds.id=?", record.id).present?)
      )
  end

  def timeline?
    update?
  end

  def create?
    (user.entity_id == record.entity_id) && user.enable_funds
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
