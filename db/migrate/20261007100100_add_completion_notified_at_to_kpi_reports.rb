# Evidence for the KPI report journey's optional "Send completion email" step: set when the email is
# sent, cleared by any undo so it can be sent again.
# Worked examples H8, E10, E12 — openspec/changes/kpi-report-journey/design.md#worked-examples
class AddCompletionNotifiedAtToKpiReports < ActiveRecord::Migration[8.1]
  def change
    add_column :kpi_reports, :completion_notified_at, :datetime
  end
end
