class ChangeDashboardWidgetDefault < ActiveRecord::Migration[7.2]
  def change
    # change the default value for display_name
    change_column_default :dashboard_widgets, :display_name, from: true, to: false
    change_column_default :dashboard_widgets, :enabled, from: false,  to: true
  end
end
