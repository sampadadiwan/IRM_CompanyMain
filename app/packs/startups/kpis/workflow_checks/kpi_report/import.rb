# 4. Import workbook — the report's current workbook finished importing without blocking errors, and the
# report has KPIs. KPIs typed straight onto a report without a workbook count as imported.
#
# Fund uploads never set import_status, so the evidence is the stored verdict for the current document
# (validation_result) — written by ImportKpiWorkbookJob or the edit page's re-check — plus the KPIs.
# Worked examples H3, E5 — openspec/changes/kpi-report-journey/design.md#worked-examples
module WorkflowChecks
  module KpiReport
    class Import < WorkflowChecks::Base
      include Support

      self.key = "kpi_report.import"
      self.label = "Import workbook"
      self.workflowable_type = "KpiReport"
      self.how = "Upload the KPI workbook on the report; the import runs in the background."
      self.why = "The KPI values come from the workbook."
      self.effects = "The KPIs are staged for approval. Nothing is sent to the portfolio company."

      def call(report)
        workbook = current_workbook(report)
        has_kpis = report.kpis.exists?

        # No workbook at all: KPIs entered by hand pass; otherwise one has to be uploaded
        unless workbook
          return pass(message: "KPIs entered on the report") if has_kpis

          return fail_with(message: "No KPI workbook uploaded yet", action_label: "Edit report", action_path: edit_report_path(report))
        end

        # A portco submission says outright whether its import is still running (import_status). The
        # stored verdict must be about the current workbook; it may come from the import job ("import")
        # or from the edit page's re-check of the same document ("document"), which is written after
        # the save — so it can land after the job's verdict and replace it.
        verdict = report.validation_result || {}
        checked = %w[import document].include?(verdict["source"]) && verdict["document_id"].to_i == workbook.id
        return fail_with(message: "Import running") if report.import_status == "pending" || !checked

        unless verdict["ok"]
          return fail_with(message: "Import had blocking errors — fix the workbook and upload it again",
                           action_label: "Edit report", action_path: edit_report_path(report))
        end

        # E5: every KPI was rejected, or the workbook had no column for this report's period
        unless has_kpis
          return fail_with(message: "No KPIs on this report — they were rejected, or the workbook had no column for this period",
                           action_label: "Edit report", action_path: edit_report_path(report))
        end

        pass(message: "Workbook imported", passed_since: report.validated_at)
      end
    end
  end
end
