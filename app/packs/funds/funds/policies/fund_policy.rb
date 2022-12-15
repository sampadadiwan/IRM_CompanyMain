class FundPolicy < FundBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      elsif user.curr_role == "fund_manager" && user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "fund_manager"
        scope.for_employee(user)
      elsif user.curr_role == "advisor"
        scope.for_advisor(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    user.enable_funds
  end

  def report?
    update?
  end

  def show?
    user.enable_funds &&
      (
        permissioned_employee? ||
        permissioned_advisor?  ||
        permissioned_investor?
      )
  end

  def last?
    update?
  end

  def timeline?
    update?
  end

  def create?
    user.enable_funds && (user.entity_id == record.entity_id)
  end

  def new?
    user.has_cached_role?(:company_admin) && user.curr_role == "fund_manager"
  end

  def update?
    permissioned_employee?(:update) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    false
    # permissioned_employee?(:destroy) ||
    #   permissioned_advisor?(:destroy)
  end
end
