class CapitalRemittancePaymentPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role.to_sym == :employee
        scope.for_employee(user)
      elsif user.entity_type == "Group Company"
        scope.for_parent_employee(user)
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
      permissioned_investor?
  end

  def new?
    create?
  end

  def verify?
    update?
  end

  def update?
    permissioned_investor? ||
      permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    permissioned_employee?(:destroy)
  end
end
