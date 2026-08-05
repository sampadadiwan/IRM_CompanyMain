# Service for sending schedule-based notifications for agent execution outcomes.
#
# Handles notifications for:
# - Failure (after all retries exhausted)
# - Success (when notify_on_success is enabled)
# - Partial Success (when notify_on_partial_success is enabled)
# - Internal error reports (when notify_caphive_on_error is enabled)
#
# Uses the Noticed gem pattern for multi-channel delivery (email, WhatsApp, in-app).
#
# @example Sending failure notification
#   AgentFailureNotifier.new(execution_log).call
#
# @example Sending success notification
#   AgentFailureNotifier.new(execution_log).notify_success
#
# @see AgentSchedulerNotifier
# @see AgentRunnerJob
class AgentFailureNotifier
  # Initializes the notifier with an execution log.
  #
  # @param execution_log [AgentExecutionLog] the execution to notify about
  def initialize(execution_log)
    @execution_log = execution_log
    @schedule = execution_log.agent_schedule
    @support_agent = execution_log.support_agent
    @entity = execution_log.entity
  end

  # Sends failure notification to configured users (called when all retries exhausted).
  #
  # @return [void]
  def call
    notify_failure
  end

  # Sends failure notification if enabled in schedule settings.
  #
  # @return [void]
  def notify_failure
    return unless should_notify?(:failure)

    send_notifications(:agent_failure)
    send_internal_notification

    Rails.logger.info("[AgentFailureNotifier] Sent failure notifications for execution_log #{@execution_log.id}")
  end

  # Sends success notification if enabled in schedule settings.
  #
  # @return [void]
  def notify_success
    return unless should_notify?(:success)

    send_notifications(:agent_success)

    Rails.logger.info("[AgentFailureNotifier] Sent success notifications for execution_log #{@execution_log.id}")
  end

  # Sends partial success notification if enabled in schedule settings.
  #
  # @return [void]
  def notify_partial_success
    return unless should_notify?(:partial_success)

    send_notifications(:agent_partial_success)
    send_internal_notification

    Rails.logger.info("[AgentFailureNotifier] Sent partial success notifications for execution_log #{@execution_log.id}")
  end

  private

  # Determines if notifications should be sent based on schedule configuration.
  #
  # @param notification_type [Symbol] :success, :failure, or :partial_success
  # @return [Boolean] true if notifications are enabled for this type
  def should_notify?(notification_type)
    # Manual runs have no schedule to configure notifications on — always email
    # failures/partial successes to the user who triggered the run (they asked
    # for it and the in-app toast is transient). Successes stay in-app only.
    return %i[failure partial_success].include?(notification_type) if @schedule.nil?
    return false if @schedule.failure_notification_user_ids.blank?

    case notification_type
    when :success
      @schedule.notify_on_success?
    when :failure
      @schedule.notify_on_failure?
    when :partial_success
      @schedule.notify_on_partial_success?
    else
      false
    end
  end

  # Sends notifications to all configured users via Noticed.
  #
  # @param email_method [Symbol] the mailer method to use
  # @return [void]
  def send_notifications(email_method)
    users_to_notify.each do |user|
      AgentSchedulerNotifier.with(
        record: @execution_log,
        entity_id: @entity.id,
        email_method: email_method,
        user_id: user.id
      ).deliver_later(user)
    end
  end

  # Sends internal error notification to support team.
  #
  # @return [void]
  def send_internal_notification
    AgentSchedulerMailer.with(
      execution_log_id: @execution_log.id,
      entity_id: @entity.id
    ).agent_error_internal.deliver_later
  end

  # Returns the users configured to receive notifications.
  # Manual (schedule-less) runs notify the user who triggered them; an empty
  # relation (e.g. system-triggered with no user) means only the internal
  # support notification goes out.
  #
  # @return [ActiveRecord::Relation<User>] users to notify
  def users_to_notify
    return User.where(id: @execution_log.triggered_by&.id) if @schedule.nil?

    User.where(id: @schedule.failure_notification_user_ids)
  end
end
