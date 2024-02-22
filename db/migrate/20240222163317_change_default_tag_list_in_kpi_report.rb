class ChangeDefaultTagListInKpiReport < ActiveRecord::Migration[7.1]
  def change
    change_column_default :kpi_reports, :tag_list, from: nil, to: ""
  end
end
