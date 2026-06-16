# Sidekiq job that executes a support agent for a given execution log.
#
# This is the core execution job in the agent scheduler framework. It:
# 1. Marks the execution as running
# 2. Instantiates and runs the agent against all targets
# 3. Handles success/failure status updates
# 4. Manages automatic retries based on schedule configuration
# 5. Sends failure notifications when all retries are exhausted
#
# @example Enqueueing directly (typically done by SchedulerPollingJob)
#   AgentRunnerJob.perform_async(execution_log.id)
#
# @note Uses custom retry handling instead of Sidekiq's built-in retry mechanism
#   to support configurable per-schedule retry counts and intervals.
#
# @see AgentExecutionLog
# @see SchedulerPollingJob
# @see AgentFailureNotifier
class AgentRunnerJob
  include Sidekiq::Job

  sidekiq_options queue: 'agents', retry: false # Custom retry handling

  # Executes the agent for the given execution log.
  #
  # @param execution_log_id [Integer] the ID of the AgentExecutionLog to process
  # @return [void]
  # @raise [ActiveRecord::RecordNotFound] if the execution log doesn't exist
  def perform(execution_log_id)
    @execution_log = AgentExecutionLog.find(execution_log_id)
    @support_agent = @execution_log.support_agent
    @entity = @execution_log.entity
    @schedule = @execution_log.agent_schedule

    Rails.logger.info("[AgentRunnerJob] Starting execution_log #{execution_log_id} for agent #{@support_agent.agent_type}")

    # Mark as running
    @execution_log.mark_running!

    # Execute the agent
    result = execute_agent

    if result[:success]
      handle_success(result)
    else
      handle_failure(result[:error])
    end
  rescue StandardError => e
    handle_failure(e.message)
  end

  private

  # Executes the agent against all targets and collects results.
  # Continues processing even when individual targets fail.
  #
  # @return [Hash] result hash with :status, :successes, :errors, :summary
  def execute_agent
    targets = @support_agent.agent.new.targets(@entity.id)

    # Special handling for PortfolioCompanyAgent: process as batch with shared context
    return execute_portfolio_company_batch(targets) if @support_agent.agent_type == "PortfolioCompanyAgent" && targets.many?

    # Default: process each target individually
    successes = []
    errors = []

    targets.each do |target|
      result = process_single_target(target)

      if result[:success]
        successes << result
      else
        errors << result
      end
    end

    build_execution_result(successes, errors)
  end

  # Executes PortfolioCompanyAgent as a scheduled batch.
  # Delegates to PortfolioCompanyAgent.process_batch (same as adhoc path) with
  # execution_mode: :scheduled so notifications are batched and the chart job
  # runs silently without per-company chat UI.
  #
  # @param targets [Array] portfolio company targets
  # @return [Hash] execution result
  def execute_portfolio_company_batch(targets)
    result = @support_agent.agent.process_batch(
      support_agent_id: @support_agent.id,
      targets: targets,
      user_id: nil,
      entity_id: @entity.id,
      execution_mode: :scheduled
    )

    successes = result[:successes].map do |s|
      { success: true, target_id: s[:id], target_name: s[:name] }
    end

    errors = result[:errors].map do |e|
      { success: false, target_id: e[:target_id], target_name: e[:target_name], error: e[:error] }
    end

    build_execution_result(successes, errors)
  end

  # Processes a single target and returns the result.
  #
  # @param target [Object] the target to process
  # @return [Hash] result with :success, :target_id, :target_name, and :error (if failed)
  def process_single_target(target)
    @support_agent.agent.call(
      support_agent_id: @support_agent.id,
      target: target,
      entity_id: @entity.id
    )

    {
      success: true,
      target_id: target.id,
      target_name: target.try(:name) || target.try(:to_s)
    }
  rescue StandardError => e
    Rails.logger.error("[AgentRunnerJob] Error processing target #{target.id}: #{e.message}")

    {
      success: false,
      target_id: target.id,
      target_name: target.try(:name) || target.try(:to_s),
      error: e.message,
      backtrace: e.backtrace&.first(5)
    }
  end

  # Builds the execution result based on successes and errors.
  #
  # @param successes [Array<Hash>] successful target results
  # @param errors [Array<Hash>] failed target results
  # @return [Hash] consolidated result
  def build_execution_result(successes, errors)
    status = if errors.empty?
               :completed
             elsif successes.empty?
               :failed
             else
               :partial_success
             end

    {
      status: status,
      success: status != :failed,
      successes: successes,
      errors: errors,
      summary: {
        processed: successes.count,
        failed: errors.count,
        total: successes.count + errors.count
      }
    }
  end

  # Handles successful agent execution by updating the execution log and schedule.
  #
  # @param result [Hash] the execution result containing :status, :summary, :errors
  # @return [void]
  def handle_success(result)
    status = result[:status] || :completed
    @execution_log.mark_completed!(result[:summary], status: status)

    # Update schedule last_run_at
    @schedule&.update_columns(last_run_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations

    # Send agent-specific notifications (tag-based)
    send_success_notification(result) if result[:successes]&.any?
    send_error_notification(result[:errors]) if result[:errors]&.any?

    # Send schedule-based notifications
    send_schedule_notification(status)

    Rails.logger.info("[AgentRunnerJob] Completed execution_log #{@execution_log.id} with status: #{status}")
  end

  # Handles failed agent execution by updating status and managing retries/notifications.
  #
  # @param error_message [String] description of what went wrong
  # @return [void]
  def handle_failure(error_message)
    @execution_log.mark_failed!(error_message)

    Rails.logger.error("[AgentRunnerJob] Failed execution_log #{@execution_log.id}: #{error_message}")

    if should_retry?
      schedule_retry
    else
      send_failure_notification
    end
  end

  # Determines if this execution should be retried based on schedule configuration.
  #
  # @return [Boolean] true if retry is allowed (has schedule with retries and attempts remaining)
  def should_retry?
    return false unless @schedule
    return false if @schedule.retry_count.zero?

    @execution_log.attempt_number < (@schedule.retry_count + 1)
  end

  # Schedules a retry attempt by creating a new execution log with incremented attempt number.
  # Respects the configured retry_interval_minutes delay.
  #
  # @return [void]
  def schedule_retry
    # Create new execution log for retry
    retry_log = AgentExecutionLog.create!(
      agent_schedule: @schedule,
      support_agent: @support_agent,
      entity: @entity,
      trigger_type: @execution_log.trigger_type,
      triggered_by: @execution_log.triggered_by,
      status: 'queued',
      attempt_number: @execution_log.attempt_number + 1
    )

    # Schedule retry after interval
    delay_seconds = (@schedule.retry_interval_minutes || 0) * 60

    if delay_seconds.positive?
      AgentRunnerJob.perform_in(delay_seconds, retry_log.id)
    else
      AgentRunnerJob.perform_async(retry_log.id)
    end

    Rails.logger.info("[AgentRunnerJob] Scheduled retry #{retry_log.attempt_number} for execution_log #{retry_log.id} in #{delay_seconds}s")
  end

  # Sends failure notification to configured users when all retries are exhausted.
  #
  # @return [void]
  def send_failure_notification
    return unless @schedule&.notify_on_failure?

    AgentFailureNotifier.new(@execution_log).call
  end

  # Sends success notification for completed targets.
  #
  # @param result [Hash] execution result with successes
  # @return [void]
  def send_success_notification(result)
    AgentNotificationService.new(
      entity: @entity,
      execution_log: @execution_log
    ).notify_success(result)
  rescue StandardError => e
    Rails.logger.error("[AgentRunnerJob] Failed to send success notification: #{e.message}")
  end

  # Sends error notification for failed targets.
  #
  # @param errors [Array<Hash>] list of errors
  # @return [void]
  def send_error_notification(errors)
    AgentNotificationService.new(
      entity: @entity,
      execution_log: @execution_log
    ).notify_errors(errors)
  rescue StandardError => e
    Rails.logger.error("[AgentRunnerJob] Failed to send error notification: #{e.message}")
  end

  # Sends schedule-based notifications based on execution outcome.
  #
  # @param status [Symbol] :completed or :partial_success
  # @return [void]
  def send_schedule_notification(status)
    return unless @schedule

    notifier = AgentFailureNotifier.new(@execution_log)

    case status
    when :completed
      notifier.notify_success
    when :partial_success
      notifier.notify_partial_success
    end
  rescue StandardError => e
    Rails.logger.error("[AgentRunnerJob] Failed to send schedule notification: #{e.message}")
  end
end
