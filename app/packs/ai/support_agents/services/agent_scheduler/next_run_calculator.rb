# Calculates the next scheduled run time for an AgentSchedule.
#
# This service handles timezone-aware scheduling for various frequencies
# (daily, weekly, monthly, bimonthly, quarterly, half-yearly). It correctly
# handles edge cases like:
# - Day 31 in months with fewer days (uses last day of month)
# - Times that have already passed today
# - Timezone conversions between user timezone and UTC storage
#
# @example Calculate next run time
#   calculator = NextRunCalculator.new(schedule)
#   next_run_utc = calculator.calculate
#
# @example Calculate from a specific time (useful for testing)
#   calculator = NextRunCalculator.new(schedule, 1.week.from_now)
#   next_run_utc = calculator.calculate
#
# @see AgentSchedule
class NextRunCalculator
  # Initializes the calculator with a schedule and optional reference time.
  #
  # @param schedule [AgentSchedule] the schedule to calculate next run for
  # @param from_time [Time] reference time to calculate from (defaults to current time)
  def initialize(schedule, from_time = Time.current)
    @schedule = schedule
    @from_time = from_time
  end

  # Calculates the next run time based on the schedule's frequency and configuration.
  #
  # @return [Time, nil] the next run time in UTC, or nil if schedule is disabled
  def calculate
    return nil unless @schedule.enabled?

    time_in_zone = @from_time.in_time_zone(@schedule.timezone)

    next_run = case @schedule.frequency
               when 'daily'
                 calculate_daily(time_in_zone)
               when 'weekly'
                 calculate_weekly(time_in_zone)
               when 'monthly'
                 calculate_monthly(time_in_zone, 1)
               when 'bimonthly'
                 calculate_monthly(time_in_zone, 2)
               when 'quarterly'
                 calculate_monthly(time_in_zone, 3)
               when 'half_yearly'
                 calculate_monthly(time_in_zone, 6)
               end

    # Convert back to UTC for storage
    next_run&.utc
  end

  private

  # Calculates next run for daily frequency.
  # If the time has passed today, returns tomorrow at the scheduled time.
  #
  # @param time_in_zone [ActiveSupport::TimeWithZone] current time in schedule's timezone
  # @return [ActiveSupport::TimeWithZone] next run time in schedule's timezone
  def calculate_daily(time_in_zone)
    run_time = build_time_today(time_in_zone)

    # If time already passed today, move to tomorrow
    run_time <= time_in_zone ? run_time + 1.day : run_time
  end

  # Calculates next run for weekly frequency.
  # Uses run_on_day (0=Sunday, 6=Saturday) to determine which day of week.
  #
  # @param time_in_zone [ActiveSupport::TimeWithZone] current time in schedule's timezone
  # @return [ActiveSupport::TimeWithZone] next run time in schedule's timezone
  def calculate_weekly(time_in_zone)
    target_wday = @schedule.run_on_day # 0 = Sunday, 6 = Saturday
    current_wday = time_in_zone.wday

    days_until_target = (target_wday - current_wday) % 7
    target_date = time_in_zone.to_date + days_until_target.days

    run_time = build_time_on_date(target_date, time_in_zone)

    # If it's today but time has passed, move to next week
    run_time += 7.days if days_until_target.zero? && run_time <= time_in_zone

    run_time
  end

  # Calculates next run for monthly-based frequencies (monthly, bimonthly, quarterly, half-yearly).
  # Uses run_on_day (1-31) to determine which day of month.
  #
  # @param time_in_zone [ActiveSupport::TimeWithZone] current time in schedule's timezone
  # @param month_interval [Integer] number of months between runs (1=monthly, 3=quarterly, etc.)
  # @return [ActiveSupport::TimeWithZone] next run time in schedule's timezone
  def calculate_monthly(time_in_zone, month_interval)
    target_day = @schedule.run_on_day
    current_date = time_in_zone.to_date

    # Start with current month
    target_date = safe_date(current_date.year, current_date.month, target_day)
    run_time = build_time_on_date(target_date, time_in_zone)

    # If date/time has passed, move forward by month_interval
    if run_time <= time_in_zone
      next_month_date = current_date >> month_interval
      target_date = safe_date(next_month_date.year, next_month_date.month, target_day)
      run_time = build_time_on_date(target_date, time_in_zone)
    end

    run_time
  end

  # Builds a time object for today at the scheduled run_at_time.
  #
  # @param time_in_zone [ActiveSupport::TimeWithZone] reference time for the timezone
  # @return [ActiveSupport::TimeWithZone] today at the scheduled time
  def build_time_today(time_in_zone)
    time_in_zone.change(
      hour: @schedule.run_at_time.hour,
      min: @schedule.run_at_time.min,
      sec: 0
    )
  end

  # Builds a time object for a specific date at the scheduled run_at_time.
  #
  # @param date [Date] the target date
  # @param time_in_zone [ActiveSupport::TimeWithZone] reference time for the timezone
  # @return [ActiveSupport::TimeWithZone] the date at the scheduled time
  def build_time_on_date(date, time_in_zone)
    time_in_zone.change(
      year: date.year,
      month: date.month,
      day: date.day,
      hour: @schedule.run_at_time.hour,
      min: @schedule.run_at_time.min,
      sec: 0
    )
  end

  # Creates a safe Date object, handling months with fewer than 31 days.
  # If the requested day exceeds the month's last day, uses the last day.
  #
  # @param year [Integer] the year
  # @param month [Integer] the month (1-12)
  # @param day [Integer] the desired day (1-31)
  # @return [Date] the valid date, clamped to the month's last day if necessary
  def safe_date(year, month, day)
    last_day = Date.new(year, month, -1).day
    actual_day = [day, last_day].min
    Date.new(year, month, actual_day)
  end
end
