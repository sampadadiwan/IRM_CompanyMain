# One row per push attempt per phone: makes a retried Noticed delivery job harmless (no second
# push to the same phone), feeds the Devices page's "last delivery", and is the audit trail
# support reads. openspec/changes/lp-mobile-app — design card ⑥. Worked examples E35, X10, X11.
class CreateMobilePushDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_push_deliveries do |t|
      t.references :noticed_notification, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :mobile_device, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :status, limit: 10, null: false, default: "pending" # pending | sent | delivered | failed
      t.string :ticket_id, limit: 64
      t.string :error, limit: 255
      t.timestamps

      # E35 — a retried delivery job finds the row and does not push twice
      t.index %i[noticed_notification_id mobile_device_id], unique: true, name: "idx_mobile_push_deliveries_unique"
      t.index %i[mobile_device_id created_at], name: "idx_mobile_push_deliveries_device"
      t.index :ticket_id
    end
  end
end
