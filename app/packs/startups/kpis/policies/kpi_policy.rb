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
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    ((belongs_to_entity?(user, record) && parent_in_users_firms?(record.kpi_report)) || permissioned_employee?) && record.owner_id.nil?
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

  # H14: the portfolio company submits, the fund (the KPI's entity_id) reviews. Approving was a role
  # check only, so an approver or company admin of ANY firm - or an LP user holding the approver role
  # on a KPI shared with them - could approve, reject or unapprove another fund's KPIs.
  # Tests H14-1, H14-4, H14-H — features/security/kpi_approval_isolation.feature
  def approve?
    approver? && record.unapproved? && fund_reviewer?
  end

  # Rejecting deletes the staged value: the same reviewer as approving (H14-H)
  def reject?
    approve?
  end

  # Test H14-3 — features/security/kpi_approval_isolation.feature
  def unapprove?
    approver? && record.approved? && fund_reviewer?
  end

  private

  # Holds a reviewing role
  def approver?
    user.company_admin? || user.has_cached_role?(:approver)
  end

  # The KPI's own fund (or a child firm of the user's group company), the same test
  # KpiReportPolicy#mark_reviewed? uses. permissioned_employee? falls back to support, who keep
  # approving as themselves (H14-H2).
  def fund_reviewer?
    belongs_to_entity?(user, record) || permissioned_employee?
  end
end
