# Service to schedule agent runs for the current day.
#
# This service is called once daily (from DailyMorningJob at 01:30 AM) and:
# 1. Finds all enabled schedules that should run today
# 2. Creates execution logs for each
# 3. Schedules AgentRunnerJob at the configured run time
#
# @example
#   AgentDailySchedulerService.new.call
#
# @see DailyMorningJob
# @see AgentRunnerJob
class AgentDailySchedulerService
  # Schedules all agent runs that are due today.
  #
  # @return [Integer] number of schedules processed
  def call
    count = 0

    schedules_due_today.each do |schedule|
      schedule_agent_run(schedule)
      count += 1
    rescue StandardError => e
      Rails.logger.error("[AgentDailySchedulerService] Error scheduling #{schedule.id}: #{e.message}")
    end

    Rails.logger.info("[AgentDailySchedulerService] Scheduled #{count} agent run(s) for today")
    count
  end

  private

  # Finds all enabled schedules that should run today.
  #
  # @return [Array<AgentSchedule>] schedules due today
  def schedules_due_today
    AgentSchedule
      .enabled
      .includes(:support_agent, :entity)
      .select { |schedule| should_run_today?(schedule) }
  end

  # Determines if a schedule should run today based on its frequency.
  #
  # @param schedule [AgentSchedule] the schedule to check
  # @return [Boolean] true if schedule should run today
  def should_run_today?(schedule)
    today = Time.current.in_time_zone(schedule.timezone)

    case schedule.frequency
    when 'daily'
      true
    when 'weekly'
      today.wday == schedule.run_on_day
    when 'monthly'
      today.day == schedule.run_on_day || last_day_adjustment?(schedule, today, 1)
    when 'bimonthly'
      month_matches?(today, 2) && (today.day == schedule.run_on_day || last_day_adjustment?(schedule, today, 2))
    when 'quarterly'
      month_matches?(today, 3) && (today.day == schedule.run_on_day || last_day_adjustment?(schedule, today, 3))
    when 'half_yearly'
      month_matches?(today, 6) && (today.day == schedule.run_on_day || last_day_adjustment?(schedule, today, 6))
    else
      false
    end
  end

  # Checks if the run_on_day exceeds this month's days (e.g., day 31 in February).
  # If so, returns true on the last day of the month.
  #
  # @param schedule [AgentSchedule] the schedule
  # @param today [Time] current time in schedule's timezone
  # @param interval [Integer] month interval (unused, kept for consistency)
  # @return [Boolean] true if today is the adjusted run day
  def last_day_adjustment?(schedule, today, _interval)
    last_day = today.end_of_month.day
    schedule.run_on_day > last_day && today.day == last_day
  end

  # Checks if the current month aligns with the schedule's interval.
  # For quarterly (3): runs in months 1, 4, 7, 10
  # For half_yearly (6): runs in months 1, 7
  #
  # @param today [Time] current time
  # @param interval [Integer] month interval
  # @return [Boolean] true if this month is a run month
  def month_matches?(today, interval)
    (today.month % interval) == 1 || (today.month == 1)
  end

  # Schedules the agent run at the configured time.
  #
  # @param schedule [AgentSchedule] the schedule to process
  # @return [void]
  def schedule_agent_run(schedule)
    run_time = calculate_run_time(schedule)

    # Skip if run_time is in the past (already missed today)
    if run_time < Time.current
      Rails.logger.info("[AgentDailySchedulerService] Skipping schedule #{schedule.id} - run time #{run_time} already passed")
      return
    end

    # Skip if already has a queued/running execution for today
    if schedule.currently_running?
      Rails.logger.info("[AgentDailySchedulerService] Skipping schedule #{schedule.id} - already running")
      return
    end

    execution_log = create_execution_log(schedule)

    # Schedule at the configured run time
    AgentRunnerJob.perform_at(run_time, execution_log.id)

    Rails.logger.info("[AgentDailySchedulerService] Scheduled #{schedule.support_agent.agent_type} (schedule #{schedule.id}) for #{run_time}")
  end

  # Calculates the run time for today in UTC.
  #
  # @param schedule [AgentSchedule] the schedule
  # @return [Time] the run time in UTC
  def calculate_run_time(schedule)
    Time.current
        .in_time_zone(schedule.timezone)
        .change(
          hour: schedule.run_at_time.hour,
          min: schedule.run_at_time.min,
          sec: 0
        )
        .utc
  end

  # Creates an execution log for the scheduled run.
  #
  # @param schedule [AgentSchedule] the schedule
  # @return [AgentExecutionLog] the created log
  def create_execution_log(schedule)
    AgentExecutionLog.create!(
      agent_schedule: schedule,
      support_agent: schedule.support_agent,
      entity: schedule.entity,
      trigger_type: 'scheduled',
      status: 'queued',
      attempt_number: 1
    )
  end
end
