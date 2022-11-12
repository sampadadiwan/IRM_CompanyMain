class CapitalDistributionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:fund_manager) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:fund_manager)
        scope.for_employee(user)
      elsif user.has_cached_role?(:advisor)
        scope.for_advisor(user).distinct
      else
        scope.for_investor(user).distinct
      end
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor? ||
      record.fund.advisor?(user)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?
  end

  def approve?
    !record.approved && create? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def reminder?
    update?
  end
end
