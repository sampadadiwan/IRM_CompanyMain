class ChangeWidgetName < ActiveRecord::Migration[7.2]
  def change
    DashboardWidget.where("widget_name like 'Ops%'").each do |dw|
      dw.widget_name = dw.widget_name.gsub("Ops: ", "")
      dw.save
    end
  end
end
