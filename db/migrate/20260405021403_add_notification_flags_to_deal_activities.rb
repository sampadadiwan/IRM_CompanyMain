class AddNotificationFlagsToDealActivities < ActiveRecord::Migration[8.1]
  def change
    add_column :deal_activities, :notify_employees, :boolean, default: false
    add_column :deal_activities, :notify_investor, :boolean, default: false
  end
end
