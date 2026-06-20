# Tracks individual execution attempts of a scheduled or manually triggered agent.
#
# AgentExecutionLog provides an audit trail for agent runs, capturing timing,
# status, results, and any errors that occurred. Each execution progresses
# through statuses: queued -> running -> completed/failed.
#
# @example Creating a log for a scheduled run
#   AgentExecutionLog.create!(
#     agent_schedule: schedule,
#     support_agent: agent,
#     entity: entity,
#     trigger_type: 'scheduled',
#     status: 'queued',
#     attempt_number: 1
#   )
#
# @example Tracking execution lifecycle
#   log.mark_running!
#   # ... agent executes ...
#   log.mark_completed!(processed: 10, errors: 0)
#   # or on failure:
#   log.mark_failed!("Connection timeout")
#
# @see AgentSchedule
# @see AgentRunnerJob
class AgentExecutionLog < ApplicationRecord
  # @!attribute [rw] agent_schedule
  #   @return [AgentSchedule, nil] the schedule that triggered this execution (nil for manual triggers without schedule)
  belongs_to :agent_schedule, optional: true

  # @!attribute [rw] support_agent
  #   @return [SupportAgent] the agent that was executed
  belongs_to :support_agent

  # @!attribute [rw] entity
  #   @return [Entity] the entity context for this execution
  belongs_to :entity

  # @!attribute [rw] triggered_by
  #   @return [User, nil] the user who manually triggered this execution (nil for scheduled runs)
  belongs_to :triggered_by, class_name: 'User', optional: true

  # @!attribute [rw] trigger_type
  #   @return [String] how the execution was initiated ('scheduled' or 'manual')
  enum :trigger_type, {
    scheduled: 'scheduled',
    manual: 'manual'
  }, prefix: true

  # @!attribute [rw] status
  #   @return [String] current execution status ('queued', 'running', 'completed', 'failed')
  enum :status, {
    queued: 'queued',
    running: 'running',
    completed: 'completed',
    failed: 'failed',
    partial_success: 'partial_success'
  }, prefix: true

  validates :trigger_type, presence: true
  validates :status, presence: true
  validates :attempt_number, numericality: { greater_than_or_equal_to: 1 }

  # @!scope class
  # @!method recent
  #   Returns execution logs ordered by most recent first.
  #   @return [ActiveRecord::Relation<AgentExecutionLog>]
  scope :recent, -> { order(created_at: :desc) }

  # @!scope class
  # @!method for_agent_entity(agent_id, entity_id)
  #   Returns execution logs for a specific agent and entity combination.
  #   @param agent_id [Integer] the support agent ID
  #   @param entity_id [Integer] the entity ID
  #   @return [ActiveRecord::Relation<AgentExecutionLog>]
  scope :for_agent_entity, ->(agent_id, entity_id) { where(support_agent_id: agent_id, entity_id: entity_id) }

  # @!scope class
  # @!method active
  #   Returns execution logs that are currently active (queued or running).
  #   @return [ActiveRecord::Relation<AgentExecutionLog>]
  scope :active, -> { where(status: %w[queued running]) }

  # @!scope class
  # @!method by_schedule(schedule_id)
  #   Returns execution logs for a specific schedule.
  #   @param schedule_id [Integer] the agent schedule ID
  #   @return [ActiveRecord::Relation<AgentExecutionLog>]
  scope :by_schedule, ->(schedule_id) { where(agent_schedule_id: schedule_id) }

  # Transitions the execution to 'running' status and records the start time.
  #
  # @return [Boolean] true if the update succeeded
  # @raise [ActiveRecord::RecordInvalid] if the update fails validation
  def mark_running!
    update!(status: 'running', started_at: Time.current)
  end

  # Transitions the execution to 'completed' status and records the completion time.
  #
  # @param summary [Hash, String, nil] optional summary of the execution results
  # @param status [String] execution status (default: 'completed', can be 'partial_success')
  # @return [Boolean] true if the update succeeded
  # @raise [ActiveRecord::RecordInvalid] if the update fails validation
  def mark_completed!(summary = nil, status: 'completed')
    update!(
      status: status,
      completed_at: Time.current,
      result_summary: summary
    )
  end

  # Transitions the execution to 'failed' status and records the error.
  #
  # @param error_msg [String] description of the error that caused the failure
  # @return [Boolean] true if the update succeeded
  # @raise [ActiveRecord::RecordInvalid] if the update fails validation
  def mark_failed!(error_msg)
    update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error_msg
    )
  end

  # Calculates the execution duration in seconds.
  #
  # @return [Float, nil] duration in seconds, or nil if execution hasn't completed
  def duration
    return nil unless started_at && completed_at

    completed_at - started_at
  end

  # Returns a human-readable formatted duration string.
  #
  # @return [String, nil] formatted duration (e.g., "2m 30s", "5s", "< 1s"), or nil if not available
  def duration_formatted
    return nil unless duration
    return "< 1s" if duration < 1
    return "#{duration.to_i}s" if duration < 60

    minutes = (duration / 60).to_i
    seconds = (duration % 60).to_i
    seconds.zero? ? "#{minutes}m" : "#{minutes}m #{seconds}s"
  end

  # Determines if this execution can be retried based on schedule retry settings.
  #
  # @return [Boolean] true if retry is allowed (failed status and attempts remaining)
  def can_retry?
    return false unless status_failed?
    return false unless agent_schedule

    attempt_number < (agent_schedule.retry_count + 1)
  end
end
