class AddKpiReminderToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :kpi_reminder_frequency, :string, limit: 10
    add_column :entity_settings, :kpi_reminder_before, :integer
  end
end
