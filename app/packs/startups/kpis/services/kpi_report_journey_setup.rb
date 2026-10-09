# The KPI report journey: what JourneySetup seeds for KPI reports (the seeding itself, idempotency and
# the dry run live in JourneySetup).
#
#   One template — "KPI Report Review" (6 tasks; no sign-off step)
#   One rule     — every requested KPI report → "KPI Report Review", priority 100
#
# One template for both ways KPIs arrive: when the fund uploads them itself, "Send upload request" and
# "Submit KPIs" are n/a (FundUploaded). "Send completion email" is not seeded — an admin adds it and
# picks its actors. Reports never get a journey from a save, only from KpiReport#start_journey!, so
# setup never touches existing reports.
#
# The step list below is what the KPI upload user guide documents task by task, so adding, renaming
# or removing one here means editing its journey section in docs/user_guides/kpi_upload_user_guide.md too.
# Worked examples H1, E1, E4 — openspec/changes/kpi-report-journey/design.md#worked-examples
class KpiReportJourneySetup < JourneySetup
  WORKFLOWABLE_TYPE = "KpiReport".freeze
  KEY_PREFIX = "kpi_report.".freeze
  LABEL = "KPI report journeys".freeze
  RECORD = "KPI report".freeze # what the setup menu's messages call one record
  FULL_KEY = "kpi_report_full".freeze
  FULL_NAME = "KPI Report Review".freeze
  FULL_LABEL = "KPI report".freeze
  DESCRIPTION = "Tracks each requested KPI report from KPI mappings to closing. Seeded by CapHive; " \
                "admins can add a Send completion email step or remove tasks.".freeze
  # No sign-off: JourneySetup neither seeds nor backfills one for this kind
  SIGN_OFF_NAME = nil

  # [name, kind, check, skip, unlocks, description]
  FULL_STEPS = [
    ["Set up KPI mappings", "system", "setup_mappings", nil, nil,
     "The portfolio company has at least one KPI mapping an import can fill."],
    ["Send upload request", "system", "send_request", "fund_uploaded", nil,
     "The portfolio company has been emailed the upload link. Not applicable when the fund uploads the KPIs."],
    ["Submit KPIs", "system", "submit", "fund_uploaded", nil,
     "The portfolio company submitted the report. Not applicable when the fund uploads the KPIs."],
    ["Import workbook", "system", "import", nil, nil,
     "The report's workbook imported without blocking errors and the report has KPIs."],
    ["Approve or reject KPIs", "system", "approve", nil, nil,
     "No KPI of the portfolio company is still waiting for approval, on any period."],
    ["Close report", "system", "close", nil, nil,
     "Someone clicked Close report, approving anything still pending and marking the report reviewed."]
  ].freeze

  # Offered only to funds that use KPIs
  def self.available_for?(entity)
    super && entity.enable_kpis
  end
end
