class AddDisplayNameToDashboardWidget < ActiveRecord::Migration[7.2]
  def change
    add_column :dashboard_widgets, :display_name, :boolean, default: true 
    add_column :dashboard_widgets, :display_tag, :boolean, default: false
  end
end
