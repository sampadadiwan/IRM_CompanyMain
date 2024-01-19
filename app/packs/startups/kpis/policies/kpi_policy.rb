class KpiPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        scope.for_investor(user)
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    user.enable_kpis
  end

  def show?
    user.enable_kpis &&
      (belongs_to_entity?(user, record) || permissioned_employee? || permissioned_investor?)
  end

  def create?
    belongs_to_entity?(user, record)
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
