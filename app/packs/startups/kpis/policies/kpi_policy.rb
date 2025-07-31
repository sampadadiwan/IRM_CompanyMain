class KpiPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        # for_investor_sql = scope.for_investor(user).to_sql
        # all_my_kpis_sql = Kpi.where(entity_id: user.entity_id).to_sql
        # sql = "#{for_investor_sql} UNION #{all_my_kpis_sql}"
        # scope.from("(#{sql}) as kpis")
        scope.for_investor(user)
      else
        scope.where(entity_id: user.entity_id).where(owner_id: nil)
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
    (belongs_to_entity?(user, record) || permissioned_employee?) && record.owner_id.nil?
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
