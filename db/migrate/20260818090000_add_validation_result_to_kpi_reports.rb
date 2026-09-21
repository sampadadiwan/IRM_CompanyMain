# Stores the last KpiWorkbookReader#validate verdict on the report so the portco's
# panel and the fund's pending dashboard can show it without re-parsing the workbook.
# Display only — the submit gate always recomputes (docs/modules/portfolio/kpis/kpi_portco_upload_validation_review.md §2.10).
class AddValidationResultToKpiReports < ActiveRecord::Migration[8.1]
  def change
    change_table :kpi_reports, bulk: true do |t|
      t.json :validation_result
      t.datetime :validated_at
    end
  end
end
