# Represents a scheduled execution configuration for a SupportAgent.
#
# AgentSchedule defines when and how often a support agent should run automatically.
# It supports various frequencies (daily, weekly, monthly, etc.) and handles
# timezone-aware scheduling with automatic next_run_at calculation.
#
# @example Creating a daily schedule
#   AgentSchedule.create!(
#     support_agent: agent,
#     entity: entity,
#     frequency: 'daily',
#     run_at_time: '09:00',
#     timezone: 'America/New_York',
#     enabled: true
#   )
#
# @example Creating a weekly schedule (every Monday)
#   AgentSchedule.create!(
#     support_agent: agent,
#     entity: entity,
#     frequency: 'weekly',
#     run_on_day: 1, # Monday
#     run_at_time: '14:30',
#     timezone: 'UTC'
#   )
#
# @see AgentExecutionLog
# @see NextRunCalculator
# @see SchedulerPollingJob
class AgentSchedule < ApplicationRecord
  include Schedulable

  # @!attribute [rw] support_agent
  #   @return [SupportAgent] the agent to be scheduled
  belongs_to :support_agent

  # @!attribute [rw] entity
  #   @return [Entity] the entity context for the scheduled agent run
  belongs_to :entity

  # @!attribute [rw] created_by
  #   @return [User, nil] the user who created this schedule
  belongs_to :created_by, class_name: 'User', optional: true

  # @!attribute [r] execution_logs
  #   @return [ActiveRecord::Relation<AgentExecutionLog>] logs of all executions for this schedule
  has_many :execution_logs, class_name: 'AgentExecutionLog', dependent: :nullify

  # @!attribute [rw] failure_notification_user_ids
  #   @return [Array<Integer>] IDs of users to notify on failure
  attribute :failure_notification_user_ids, default: -> { [] }

  # notify_on_success, notify_on_partial_success, and notify_caphive_on_error
  # are database columns with defaults defined in the migration.

  # @!attribute [rw] frequency
  #   @return [String] how often the agent runs ('daily', 'weekly', 'monthly', 'bimonthly', 'quarterly', 'half_yearly')
  enum :frequency, {
    daily: 'daily',
    weekly: 'weekly',
    monthly: 'monthly',
    bimonthly: 'bimonthly',
    quarterly: 'quarterly',
    half_yearly: 'half_yearly'
  }, prefix: true

  validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
  validates :retry_interval_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :support_agent_id, uniqueness: { scope: :entity_id, message: 'already has a schedule for this entity' }

  # Curated list of commonly used timezones for display in forms.
  # Each entry is [timezone_identifier, display_name].
  # @return [Array<Array(String, String)>]
  CURATED_TIMEZONES = [
    ['UTC', 'UTC'],
    ['Asia/Kolkata', 'India Standard Time (IST)'],
    ['Asia/Singapore', 'Singapore Time (SGT)'],
    ['Asia/Tokyo', 'Japan Standard Time (JST)'],
    ['Asia/Dubai', 'Gulf Standard Time (GST)'],
    ['Asia/Hong_Kong', 'Hong Kong Time (HKT)'],
    ['Europe/London', 'British Time (GMT/BST)'],
    ['Europe/Paris', 'Central European Time (CET)'],
    ['Europe/Zurich', 'Central European Time (CET)'],
    ['America/New_York', 'Eastern Time (ET)'],
    ['America/Chicago', 'Central Time (CT)'],
    ['America/Los_Angeles', 'Pacific Time (PT)'],
    ['Australia/Sydney', 'Australian Eastern Time (AET)']
  ].freeze

  # Checks if this schedule has an active execution (queued or running).
  #
  # @return [Boolean] true if an execution is currently in progress
  def currently_running?
    execution_logs.exists?(status: %w[queued running])
  end

  # Returns the most recent execution log for this schedule.
  #
  # @return [AgentExecutionLog, nil] the last execution log, or nil if none exist
  def last_execution
    execution_logs.order(created_at: :desc).first
  end

  # Returns the users configured to receive failure notifications.
  #
  # @return [ActiveRecord::Relation<User>] users to notify on failure
  def notification_users
    User.where(id: failure_notification_user_ids)
  end
end
