class ReportBuilderSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    ReportSchedule.active.each do |schedule|
      next unless due?(schedule)

      # Trigger the export job
      # We use the report's owner as the user for the export job
      ReportBuilderExportJob.perform_later(schedule.report_id, schedule.report.user_id, schedule.id)

      # Update last run at
      schedule.update_column(:last_run_at, Time.current)
    end
  end

  private

  # Returns true when the schedule's most-recent slot has not yet been run.
  # Uses Time.current (zone-aware) so DST transitions are handled by Rails.
  def due?(schedule)
    return true if schedule.last_run_at.nil?

    slot = last_scheduled_slot(schedule)
    return false if slot.nil?

    # Due if the scheduled slot has passed and the last run predates it.
    Time.current >= slot && schedule.last_run_at < slot
  end

  # Returns the most-recent past slot at which this schedule should fire.
  # Returns nil if the slot hasn't occurred yet today/this-week/this-month.
  def last_scheduled_slot(schedule)
    now = Time.current

    case schedule.frequency
    when "daily"
      slot = now.beginning_of_day + 9.hours
      slot <= now ? slot : slot - 1.day
    when "weekly"
      # Monday = 1 in Rails wday (beginning_of_week defaults to Monday)
      slot = now.beginning_of_week(:monday) + 9.hours
      slot <= now ? slot : slot - 1.week
    when "monthly"
      slot = now.beginning_of_month + 9.hours
      slot <= now ? slot : slot - 1.month
    end
  end
end
