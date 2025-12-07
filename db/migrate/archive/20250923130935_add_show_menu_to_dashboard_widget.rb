class AddShowMenuToDashboardWidget < ActiveRecord::Migration[8.0]
  def change
    add_column :dashboard_widgets, :show_menu, :boolean, default: true, null: false
    DashboardWidget.update_all(show_menu: true)
  end
end
