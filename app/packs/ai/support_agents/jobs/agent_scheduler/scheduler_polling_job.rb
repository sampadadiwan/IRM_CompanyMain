# Sidekiq job that polls for agent schedules that are due and enqueues AgentRunnerJob.
#
# Designed to run on a short interval (e.g. every minute via a cron). It uses the
# next_run_at column on AgentSchedule to determine which schedules are due, so it
# is safe to run frequently — a schedule is only picked up once because next_run_at
# is advanced immediately after enqueuing.
#
# @see AgentRunnerJob
# @see AgentSchedule#due
class SchedulerPollingJob
  include Sidekiq::Job

  sidekiq_options queue: 'agents'

  # Finds all due schedules, creates execution logs, advances next_run_at, and
  # enqueues AgentRunnerJob for each.
  #
  # @return [void]
  def perform
    AgentSchedule.due.includes(:support_agent, :entity).find_each do |schedule|
      process_schedule(schedule)
    rescue StandardError => e
      Rails.logger.error("[SchedulerPollingJob] Error processing schedule #{schedule.id}: #{e.message}")
    end
  end

  private

  def process_schedule(schedule)
    return if schedule.currently_running?

    execution_log = AgentExecutionLog.create!(
      agent_schedule: schedule,
      support_agent: schedule.support_agent,
      entity: schedule.entity,
      trigger_type: 'scheduled',
      status: 'queued',
      attempt_number: 1
    )

    # Advance next_run_at before enqueuing so a second poll in the same minute
    # does not create a duplicate execution log.
    schedule.update_column(:next_run_at, NextRunCalculator.new(schedule).calculate)

    AgentRunnerJob.perform_async(execution_log.id)

    Rails.logger.info("[SchedulerPollingJob] Enqueued execution_log #{execution_log.id} for schedule #{schedule.id}")
  end
end
