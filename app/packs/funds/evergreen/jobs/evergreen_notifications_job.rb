# Daily evergreen notification checks (open-ended-funds § Notifications): payment reminders and
# action-needed emails before cut-offs, cut-off summaries, ready-to-confirm, overdue settlements and
# lock-up expiries. Each notification is sent once (EvergreenNotificationLog), so re-runs are safe.
class EvergreenNotificationsJob < ApplicationJob
  queue_as :default

  def perform
    Chewy.strategy(:sidekiq) do
      EvergreenFundSetting.includes(:fund).find_each do |setting|
        next unless setting.fund&.evergreen?

        EvergreenAlerts.daily(setting)
      rescue StandardError => e
        # One fund's failure must not stop the others
        Rails.logger.error("[EvergreenNotificationsJob] fund #{setting.fund_id}: #{e.class}: #{e.message}")
        ErrorReport.notify(e, job: self, entity_id: setting.entity_id, message: "Evergreen daily notifications failed for #{setting.fund&.name} (fund #{setting.fund_id})")
      end
    end
  end
end
