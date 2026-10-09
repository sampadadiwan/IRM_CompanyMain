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

      Rails.logger.debug "Send scheduled Reminders"
      ReminderJob.perform_now

      Rails.logger.debug "Cleanup of InvestorNotice which are expired"
      InvestorNoticeJob.perform_now

      Rails.logger.debug "Disable SupportClientMappings after end_date"
      SupportClientMapping.disable_expired
      SupportClientMapping.where('enabled = ? and end_date < ?', false, Time.zone.today - 1.week).find_each(&:destroy)

      # Auto lock the Allocation runs which are a week old
      Rails.logger.debug "Auto lock the Allocation runs which are a week old"
      AllocationRun.where('locked = ? and created_at < ?', false, Time.zone.today - 1.week).update(locked: true)

      # Generate Report Insights for any reports scheduled for generation today
      Rails.logger.debug "Generate Report Insights for any reports scheduled for generation today"
      index = 0
      Report.where(notify_next_run_at: Time.zone.now.all_day).order(:notify_next_run_at).find_each do |report|
        GenerateReportInsightJob.set(wait: index * 10.seconds).perform_later(report.id, user_id: nil)
        index += 1
      end

      # Schedule Agent Runs for today
      Rails.logger.debug "Schedule Agent Runs for today"
      AgentDailySchedulerService.new.call
      # Schedule Cash Flow staleness reminders
      Rails.logger.debug "Check Cash Flow staleness reminders"
      CashFlowStalenessReminderService.new.call

      # Changed: Module 8 — daily NDA expiry check for approaching/expired alerts.
      # Why: Scans all enabled NDA configs for time-based expiry (fixed_period,
      #   specific_date). NdaExpiryReminder dedup prevents re-alerts on subsequent runs.
      Rails.logger.debug "Check NDA expiry alerts"
      NdaExpiryCheckJob.perform_now

      Rails.logger.debug "Entity DB Dump Job"
      EntityDbDumpJob.perform_later
    rescue StandardError => e
      message = "Error in DailyMorningJob: #{e.message}"
      Rails.logger.error message
      Rails.logger.error e.backtrace.join("\n")
      ErrorReport.notify(e, job: self, message:)
    end
    # rubocop:enable Metrics/BlockLength
  end
end
