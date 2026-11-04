class InvestorKpiMappingPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_kpis
  end

  # L12 — generating mappings from a KPI report creates them, so it needs what new? needs: the
  # company in the user's firm and create rights (it used to be unauthorized). Test L12-4
  def generate?
    index? && create? && permissioned_employee?(:create)
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
