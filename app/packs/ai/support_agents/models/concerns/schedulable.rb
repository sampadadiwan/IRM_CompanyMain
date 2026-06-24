# Shared scheduling behavior for any model with frequency/run_on_day/run_at_time/timezone/enabled/next_run_at columns.
# Recomputes next_run_at via NextRunCalculator whenever schedule-relevant attributes change, and exposes
# the :due scope that polling jobs use to find work (e.g. SchedulerPollingJob, ReportBuilderSchedulerJob).
#
# @see NextRunCalculator
# @see AgentSchedule
# @see ReportSchedule
module Schedulable
  extend ActiveSupport::Concern

  included do
    validates :frequency, presence: true
    validates :run_at_time, presence: true
    validates :timezone, presence: true, inclusion: { in: ActiveSupport::TimeZone::MAPPING.keys + ActiveSupport::TimeZone::MAPPING.values }
    validate :run_on_day_valid_for_frequency

    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :due, -> { enabled.where(next_run_at: ..Time.current) }

    before_save :calculate_next_run_at, if: :schedule_changed?
  end

  private

  # Determines if any schedule-related attributes have changed.
  #
  # @return [Boolean] true if schedule timing attributes were modified
  def schedule_changed?
    frequency_changed? || run_on_day_changed? || run_at_time_changed? || timezone_changed? || enabled_changed?
  end

  # Calculates and sets the next_run_at timestamp based on schedule configuration.
  #
  # @return [void]
  def calculate_next_run_at
    return unless enabled?

    self.next_run_at = NextRunCalculator.new(self).calculate
  end

  # Validates that run_on_day is appropriate for the selected frequency.
  # - Weekly: 0-6 (Sunday-Saturday)
  # - Monthly/Bimonthly/Quarterly/Half-yearly: 1-31 (day of month)
  #
  # @return [void]
  def run_on_day_valid_for_frequency
    return if run_on_day.nil?

    case frequency
    when "daily"
      # run_on_day not used for daily
    when "weekly"
      errors.add(:run_on_day, "must be between 0 (Sunday) and 6 (Saturday) for weekly frequency") unless run_on_day.between?(0, 6)
    when "monthly", "bimonthly", "quarterly", "half_yearly"
      errors.add(:run_on_day, "must be between 1 and 31 for monthly frequencies") unless run_on_day.between?(1, 31)
    end
  end
end
