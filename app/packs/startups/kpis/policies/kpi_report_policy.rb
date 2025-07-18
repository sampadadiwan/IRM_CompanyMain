class KpiReportPolicy < KpiPolicyBase
  class Scope < Scope
    def resolve
      # scope.for_user(user)
      if user.curr_role == "investor"
        # Get the kpi reports as investor and uploader of kpi reports (investors can also upload kpi reports)
        scope.for_investor(user)
      else
        # Get the kpi reports as uploader of kpi reports
        scope.for_user(user)
      end
    end
  end

  def index?
    user.enable_kpis
  end

  def show_performance?
    show?
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

  def analyze?
    permissioned_employee? && user.entity.enable_ai_chat
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
