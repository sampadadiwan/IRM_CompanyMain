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
    return true if signed_id_access?

    (user.enable_kpis &&
      (belongs_to_entity?(user, record) || permissioned_employee?)) || (portfolio_company_user? && record.tag_list == "Actual")
  end

  def create?
    return true if signed_id_access?

    # Original Fund entity user permission
    # Reference: kpi_portco_upload.md
    user.enable_kpis && (belongs_to_entity?(user, record) || permissioned_employee? || portfolio_company_user?)
  end

  def new?
    create?
  end

  def analyze?
    permissioned_employee? && user.entity.enable_ai_chat
  end

  def update?
    # Original Fund entity user permission or owner access
    # Reference: kpi_portco_upload.md
    create?
  end

  def recompute_percentage_change?
    index?
  end

  def recompute_cumulative?
    index?
  end

  # Allow sending notification reminders if the user can index reports
  # and the report has self-reporting (portco upload) enabled.
  def send_portco_notification?
    user.enable_kpis &&
      (portfolio_company_user? || InvestorPolicy.new(user, record.portfolio_company).update?) &&
      record.portfolio_company.investor_accesses.approved.exists?
  end

  def trigger_periodic_reports?
    user.enable_kpis
  end

  def edit?
    update?
  end

  def destroy?
    update? && belongs_to_entity?(user, record)
  end

  private

  # Checks if the current user belongs to the actual Portfolio Company entity
  # linked to the KPI report. This allows startups to self-report KPIs to the Fund.
  # Reference: kpi_portco_upload.md
  def portfolio_company_user?
    return false if record.portfolio_company_id.blank?

    # investor_entity_id on the portfolio_company (Investor record) points to the
    # actual entity of the startup. Note that only kpi_reports with enable_portco_upload
    # set to true should allow this access.
    record.enable_portco_upload && record.portfolio_company.investor_entity_id == user.entity_id
  end
end
