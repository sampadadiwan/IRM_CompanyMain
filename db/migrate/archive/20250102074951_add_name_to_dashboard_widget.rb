class AddNameToDashboardWidget < ActiveRecord::Migration[7.2]
  def change
    add_column :dashboard_widgets, :name, :string, limit: 20, default: 'Default'
  end
end
