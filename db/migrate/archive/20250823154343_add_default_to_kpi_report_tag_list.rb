class AddDefaultToKpiReportTagList < ActiveRecord::Migration[8.0]
  def change
    change_column_default :kpi_reports, :tag_list, from: nil, to: "Actual"
    KpiReport.where(tag_list: nil).update_all(tag_list: "Actual")
    KpiReport.where(tag_list: "").update_all(tag_list: "Actual")
  end
end
