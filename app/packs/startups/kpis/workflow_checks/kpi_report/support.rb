# Shared helpers for the KPI report journey checks. Everything here reads; nothing writes.
#
# A check looks at one KPI report, its own documents and KPIs, its portfolio company's KPI mappings and
# — for approvals — the pending KPIs of that portfolio company, each with an indexed count or exists?.
# Inside this module ::KpiReport is the model; bare KpiReport is the namespace.
# Worked examples H4, H14, H15 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    module Support
      # Controls on the KPI report's OWN page (kpi_reports/show.html.erb). A step whose work is done by
      # one of these sets it as its action_target, so the journey panel clicks the real button (its
      # confirm popup still runs). Keep in step with that view; a missing target falls back to action_path.
      SEND_REQUEST_BTN = "kpi_report_send_request_btn".freeze
      CLOSE_BTN = "kpi_report_close_btn".freeze
      SEND_COMPLETION_BTN = "kpi_report_send_completion_btn".freeze

      # Statuses at or past "the portco has been asked" / "the portco has submitted"
      PAST_LINK_SENT = %w[link_sent draft_saved submitted reviewed].freeze
      SUBMITTED = %w[submitted reviewed].freeze

      private

      def routes
        Rails.application.routes.url_helpers
      end

      def report_path(report)
        routes.kpi_report_path(report)
      end

      def edit_report_path(report)
        routes.edit_kpi_report_path(report)
      end

      # The portco's own page, on its KPI mappings tab
      def mappings_path(report)
        routes.investor_path(report.portfolio_company_id, tab: "kpi-mappings-tab")
      end

      # The portco's KPI grid including staged (unapproved) values — where Approve all / Reject all live.
      # journey_report_id shows the grid's banner back to this report (kpi_reports/_journey_return_banner).
      def pending_grid_path(report)
        routes.kpi_reports_path(portfolio_company_id: report.portfolio_company_id, view_unapproved: true, grid_view: true,
                                journey_report_id: report.id)
      end

      # The portco's KPI grid, whose Actions menu also sends the upload request (Send Reminder modal) —
      # the fallback when the report page's own button isn't shown to this viewer
      def grid_path(report)
        routes.kpi_reports_path(portfolio_company_id: report.portfolio_company_id, grid_view: true)
      end

      def portco_name(report)
        report.portfolio_company&.investor_name || "the portfolio company"
      end

      # The report's current KPI workbook (a re-upload replaces it), or nil
      def current_workbook(report)
        report.documents.where(name: "KPIs").order(created_at: :desc).first
      end
    end
  end
end
