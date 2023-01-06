class CapitalRemittancePaymentPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.has_cached_role?(:employee)
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role.to_sym == :advisor
        scope.for_advisor(user)
      else
        scope.none
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

  def verify?
    update?
  end

  def update?
    permissioned_investor? ||
      permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy) ||
      permissioned_advisor?(:destroy)
  end
end
