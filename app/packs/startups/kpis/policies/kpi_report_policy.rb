class KpiReportPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      if user.curr_role == "investor"
        # for_investor_sql = scope.for_investor(user).to_sql
        # all_my_kpi_reports_sql = KpiReport.where(entity_id: user.entity_id).to_sql
        # sql = "#{for_investor_sql} UNION #{all_my_kpi_reports_sql}"
        # scope.from("(#{sql}) as kpi_reports")
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
    (user.enable_kpis &&
      ((belongs_to_entity?(user, record) || permissioned_employee?) && record.owner_id.nil?)) || permissioned_investor? || record.owner_id == user.entity_id
  end

  def create?
    (belongs_to_entity?(user, record) || permissioned_employee?) && record.owner_id.nil?
  end

  def new?
    create?
  end

  def update?
    create? || record.owner_id == user.entity_id
  end

  def recompute_percentage_change?
    index?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end
end
