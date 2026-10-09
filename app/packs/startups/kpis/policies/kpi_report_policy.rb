class KpiReportPolicy < KpiPolicyBase
  # journey? / assign_workflow? for the KPI report journey (kpi-report-journey)
  include WorkflowablePolicyMethods

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
  alias chart_refresh? index?

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
    # If the report is already submitted or reviewed, portco users cannot edit it.
    # Only fund admins/employees can edit/update it.
    return belongs_to_entity?(user, record) || permissioned_employee? if record.status_submitted? || record.status_reviewed?

    create?
  end

  def refresh_import?
    update? && user.entity_id == record.entity_id
  end

  def recompute_percentage_change?
    index?
  end

  def recompute_cumulative?
    index?
  end

  def recompute_fx_conversion?
    index?
  end

  def mark_reviewed?
    user.enable_kpis && (belongs_to_entity?(user, record) || permissioned_employee?)
  end

  def portco_pending?
    user.enable_kpis
  end

  # Allow sending notification reminders if the user owns the KPI report's entity.
  # Whether the portco has approved users is a business-logic concern checked in the job,
  # not an authorization concern.
  def send_portco_notification?
    user.enable_kpis &&
      (belongs_to_entity?(user, record) || portfolio_company_user?)
  end

  def trigger_periodic_reports?
    user.enable_kpis
  end

  def edit?
    # Portco users can view the edit page even after submission (it will be read-only).
    create?
  end

  # Dry-run workbook validation (no writes). Anyone who may open the edit page may check a file —
  # magic-link portco users included — so the pre-save panel works before anything is saved.
  def validate_upload?
    edit?
  end

  # Fund-only: reopen a submitted report and ask the portco to upload again.
  def reopen?
    mark_reviewed?
  end

  # The journey panel is for the fund only — never the portfolio company's users, who can open the
  # report itself (WorkflowablePolicyMethods#journey? would otherwise follow show?).
  # Worked examples R1 — openspec/changes/kpi-report-journey/qa-checklist.md#role-sweep
  def journey?
    show? && belongs_to_entity?(user, record)
  end

  # Fund-only, like closing the report (H8)
  def send_completion_email?
    mark_reviewed?
  end

  # Anyone who may edit (incl. magic-link portco users) may download the pre-filled workbook template.
  def template?
    edit?
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
