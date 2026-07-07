class AddIndexOnSkipReasonToNoticedNotifications < ActiveRecord::Migration[8.1]
  def change
    # skip_reason leads the index since it's non-null only for the small subset of skipped
    # notifications (everything else in this table has it null) — SkippedNotificationReportJob's
    # where.not(skip_reason: nil).where(skip_reported_at: nil) sweep can then jump straight to
    # that subset instead of scanning the whole table.
    add_index :noticed_notifications, [:skip_reason, :skip_reported_at]
  end
end
