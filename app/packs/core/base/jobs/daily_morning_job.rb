class DailyMorningJob < ApplicationJob
  def perform
    Chewy.strategy(:atomic) do
      # DocumentEsignUpdateJob.perform_now

      Rails.logger.debug "Delete old notifications"
      # We may have to increase the limit of 2 months to 1 year for certain clients who pay us more.
      Entity.joins(:noticed_events, :entity_setting).find_each do |entity|
        # Find the retention period for this entity, defaults to 2 months
        retention = entity.entity_setting.notification_retention_months.months
        Rails.logger.debug { "Deleting notifications for #{entity.name} older than #{retention} months" }
        entity.notifications.where(created_at: ..(Time.zone.today - retention)).delete_all
        entity.noticed_events.where(created_at: ..(Time.zone.today - retention)).delete_all
      end

      Rails.logger.debug "Update SecondarySale: Make expired sales inactive"
      SecondarySale.where(active: true, end_date: ..Time.zone.today).update(active: false)

      Rails.logger.debug "Generate Key Biz Metrics"
      KeyBizMetricsJob.perform_now

      Rails.logger.debug "Send scheduled Reminders"
      ReminderJob.perform_now

      Rails.logger.debug "Cleanup of InvestorNotice which are expired"
      InvestorNoticeJob.perform_now

      Rails.logger.debug "Disable SupportClientMappings after end_date"
      SupportClientMapping.disable_expired
      SupportClientMapping.where('enabled = ? and end_date < ?', false, Time.zone.today - 1.week).find_each(&:destroy)
    rescue StandardError => e
      message = "Error in DailyMorningJob: #{e.message}"
      Rails.logger.error message
      Rails.logger.error e.backtrace.join("\n")
      ExceptionNotifier.notify_exception(e, data: { message: })
    end
  end
end
