class AddNotificationFieldsToAgentSchedules < ActiveRecord::Migration[8.1]
  def change
    # New notification timing toggles
    add_column :agent_schedules, :notify_on_success, :boolean, default: false, null: false
    add_column :agent_schedules, :notify_on_partial_success, :boolean, default: true, null: false

    # Internal notification toggle
    add_column :agent_schedules, :notify_caphive_on_error, :boolean, default: true, null: false
  end
end
