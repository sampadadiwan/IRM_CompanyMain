class CreateEmailBounceEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :email_bounce_events do |t|
      t.bigint :noticed_notification_id
      t.string :tracking_id
      # Denormalized from the matched Noticed::Notification at write time so the report/policy
      # can filter by entity without a join. Nil when there's no tracking_id match.
      t.bigint :entity_id
      t.string :event_type, null: false
      t.string :bounce_type
      t.string :bounce_subtype
      t.string :complaint_feedback_type
      t.text :diagnostic_code
      t.string :recipient_email, null: false
      t.json :raw_sns_message
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    change_table :email_bounce_events, bulk: true do |t|
      t.index :noticed_notification_id
      t.index :tracking_id
      t.index :entity_id
      t.index :recipient_email
      t.index :event_type
    end
  end
end
