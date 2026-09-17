# Tracks the outcome of the KPI workbook import for portco self-reporting shells so the fund is told
# "submitted" only once the data is actually staged, and a failed import is visible rather than
# looking like a finished submission (docs/technical/kpi_portco_upload_validation_review.md §2.2 E).
class AddImportStatusToKpiReports < ActiveRecord::Migration[8.1]
  def change
    change_table :kpi_reports, bulk: true do |t|
      # nil (never imported via submit) / pending / imported / failed
      t.string :import_status, limit: 20
      # when the fund was notified of this submission — guards against duplicate notifications
      t.datetime :fund_notified_at
    end
  end
end
