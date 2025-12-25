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
      (belongs_to_entity?(user, record) || permissioned_employee?) && record.owner_id.nil?) || permissioned_investor? || record.owner_id == user.entity_id || portfolio_company_user?
  end

  def create?
    # Original Fund entity user permission
    # Reference: kpi_portco_upload.md
    ((belongs_to_entity?(user, record) || permissioned_employee?) && record.owner_id.nil?) ||
      portfolio_company_user?
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
    create? || record.owner_id == user.entity_id
  end

  def recompute_percentage_change?
    index?
  end

  # Allow sending notification reminders if the user can index reports
  # and the report has self-reporting (portco upload) enabled.
  def send_portco_notification?
    update? && record.portfolio_company.investor_accesses.approved.exists?
  end

  def edit?
    update?
  end

  def destroy?
    update?
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
