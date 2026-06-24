# Polls for ReportSchedules that are due and triggers ReportBuilderExportJob.
# Mirrors SchedulerPollingJob's pattern: due-ness is precomputed onto next_run_at
# (via the Schedulable concern + NextRunCalculator), so this job just has to ask
# "what's due right now" instead of recomputing schedule slots itself.
#
# @see Schedulable
# @see NextRunCalculator
# @see ReportBuilderExportJob
class ReportBuilderSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    ReportSchedule.due.find_each do |schedule|
      process_schedule(schedule)
    rescue StandardError => e
      Rails.logger.error "[ReportBuilderSchedulerJob] Error processing schedule #{schedule.id}: #{e.message}"
    end
  end

  private

  def process_schedule(schedule)
    ReportBuilderExportJob.perform_later(schedule.report_id, schedule.report.user_id, schedule.id)

    # Advance next_run_at before the next poll so it isn't picked up twice.
    schedule.update_columns(last_run_at: Time.current, next_run_at: NextRunCalculator.new(schedule).calculate)
  end
end
