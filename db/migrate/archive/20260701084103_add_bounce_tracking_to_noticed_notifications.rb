class AddBounceTrackingToNoticedNotifications < ActiveRecord::Migration[8.1]
  def change
    # Only noticed_notifications — the legacy `notifications` table has no
    # ActiveRecord model anywhere in the app (confirmed: only Noticed::Notification
    # is live), so columns there would never be read or written.
    #
    # tracking_id/entity_id: bounce tracking is scoped to notifier-driven sends only
    # (Noticed::Notification must exist) — mailers invoked directly without a
    # notification (magic links, KYC reminders, AI digest mailers, etc.) are not tagged
    # and generate no SES bounce/complaint events. See docs/modules/notifications/
    # email_bounce_complaint_detection_prd.md for the accepted coverage tradeoff.
    add_column :noticed_notifications, :tracking_id, :string
    add_column :noticed_notifications, :entity_id, :bigint
    add_column :noticed_notifications, :bounced_at, :datetime
    add_column :noticed_notifications, :bounce_type, :string
    add_column :noticed_notifications, :bounce_subtype, :string
    add_column :noticed_notifications, :complained_at, :datetime
    add_column :noticed_notifications, :complaint_feedback_type, :string

    change_table :noticed_notifications, bulk: true do |t|
      t.index :tracking_id, unique: true
      t.index :entity_id
    end
  end
end
