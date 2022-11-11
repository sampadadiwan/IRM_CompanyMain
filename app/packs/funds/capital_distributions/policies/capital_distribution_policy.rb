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
        scope.for_advisor(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id && user.has_cached_role?(:company_admin)) ||
      permissioned_employee? ||
      (user.entity_id != record.entity_id && CapitalDistribution.for_investor(user).where("capital_distributions.id=?", record.id)) ||
      record.fund.advisor?(user)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    create?
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
