# Evergreen notifications (open-ended-funds § Notifications): per-fund switches and a send-once log.
class AddEvergreenNotifications < ActiveRecord::Migration[8.1]
  def change
    # { "<notification key>" => true/false, "reminder_days" => 2, "large_redemption_pct" => 2 }; missing keys use defaults
    add_column :evergreen_fund_settings, :notifications, :json

    # One row per notification sent for a record (per day for daily checks), so re-runs never resend
    create_table :evergreen_notification_logs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :key, limit: 50, null: false
      t.string :record_type, limit: 50, null: false
      t.bigint :record_id, null: false
      t.date :sent_on, null: false
      t.datetime :created_at, null: false
    end
    add_index :evergreen_notification_logs, %i[key record_type record_id sent_on], unique: true, name: "idx_evergreen_notification_logs_once"
  end
end
