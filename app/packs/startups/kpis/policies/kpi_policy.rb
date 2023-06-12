class KpiPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.enable_kpis
  end

  def show?
    user.enable_kpis &&
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
