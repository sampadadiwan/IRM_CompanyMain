class CapitalDistributionPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:employee) && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.has_cached_role?(:employee)
        scope.for_employee(user)
      elsif user.curr_role.to_sym == :advisor
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
      permissioned_advisor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def approve?
    !record.approved && create? && user.has_cached_role?(:approver)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end

  def reminder?
    update?
  end
end
