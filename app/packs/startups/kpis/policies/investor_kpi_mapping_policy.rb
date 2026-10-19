class InvestorKpiMappingPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_kpis
  end

  def generate?
    index?
  end

  def show?
    user.enable_kpis &&
      (belongs_to_entity?(user, record) || permissioned_employee? || permissioned_investor?)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.investor)
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

  def recompute_rag?
    update?
  end
end
