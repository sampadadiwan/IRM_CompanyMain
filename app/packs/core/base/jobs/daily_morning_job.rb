class DailyMorningJob < ApplicationJob
  def perform
    Chewy.strategy(:atomic) do
      VestedJob.perform_now
      Rails.logger.debug "Entity.recompute_all"
      Entity.recompute_all
      # DocumentEsignUpdateJob.perform_now
      Rails.logger.debug "Delete old notifications"
      Noticed::Notification.where(created_at: ..(Time.zone.today - 2.months)).find_each(&:destroy)
      Noticed::Event.where(created_at: ..(Time.zone.today - 2.months)).find_each(&:destroy)

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
    rescue StandardError => e
      message = "Error in DailyMorningJob: #{e.message}"
      Rails.logger.error message
      Rails.logger.error e.backtrace.join("\n")
      ExceptionNotifier.notify_exception(e, data: { message: })
    end
  end
end
