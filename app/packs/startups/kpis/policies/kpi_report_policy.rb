class KpiReportPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Company"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Company"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      (user.entity_id == record.entity_id || permissioned_employee? || permissioned_investor?)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create? && permissioned_employee?(:create)
  end

  def update?
    create? && permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
