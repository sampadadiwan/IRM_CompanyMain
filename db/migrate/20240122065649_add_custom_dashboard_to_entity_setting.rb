class AddCustomDashboardToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :custom_dashboards, :text
  end
end
