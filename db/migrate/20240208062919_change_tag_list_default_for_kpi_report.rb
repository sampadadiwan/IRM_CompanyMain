class ChangeTagListDefaultForKpiReport < ActiveRecord::Migration[7.1]
  def up
    change_column :kpi_reports, :tag_list, :string, default: ""
  end

  def down
    change_column :kpi_reports, :tag_list, :string, default: nil
  end
end
