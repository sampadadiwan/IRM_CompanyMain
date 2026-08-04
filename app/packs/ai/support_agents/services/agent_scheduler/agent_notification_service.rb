# Generic notification service for agent execution results.
#
# This service handles two types of notifications:
# 1. Success notifications - sent to employees tagged with notify_tag (from agent config)
# 2. Error notifications - sent to support team
#
# @example
#   service = AgentNotificationService.new(entity: entity, execution_log: log)
#   service.notify_success(result)
#   service.notify_errors(errors)
#
# @see AgentRunnerJob
class AgentNotificationService
  # Initializes the notification service.
  #
  # @param entity [Entity] the entity context
  # @param execution_log [AgentExecutionLog] the execution log
  def initialize(entity:, execution_log:)
    @entity = entity
    @execution_log = execution_log
    @support_agent = execution_log.support_agent
    @config = @support_agent.json_fields || {}
  end

  # Sends success notification to tagged employees.
  #
  # @param result [Hash] execution result with :successes, :summary
  # @return [void]
  def notify_success(result)
    return unless should_notify_success?

    recipients = employees_by_tag(@config["notify_tag"])
    return if recipients.empty?

    send_success_email(recipients, result)
    send_success_in_app(recipients, result)

    Rails.logger.info("[AgentNotificationService] Sent success notification to #{recipients.count} recipient(s)")
  end

  # Sends error notification to support team.
  #
  # @param errors [Array<Hash>] list of errors with :target_id, :target_name, :error
  # @return [void]
  def notify_errors(errors)
    return if errors.blank?

    send_error_email(errors)

    Rails.logger.info("[AgentNotificationService] Sent error notification for #{errors.count} error(s)")
  end

  private

  # Determines if success notifications should be sent.
  #
  # @return [Boolean] true if notify_tag is configured
  def should_notify_success?
    @config["notify_tag"].present?
  end

  # Finds employees with the specified tag.
  #
  # @param tag [String] the employee tag to filter by
  # @return [Array<String>] list of email addresses
  def employees_by_tag(tag)
    return [] if tag.blank?

    # users have a tag_list CSV column, not a tag column — a where(tag:)
    # query raises StatementInvalid on first use
    @entity.employees.where("tag_list LIKE ?", "%#{tag}%").pluck(:email).compact
  end

  # Sends success email to recipients.
  #
  # @param recipients [Array<String>] email addresses
  # @param result [Hash] execution result
  # @return [void]
  def send_success_email(recipients, result)
    # TODO: Implement AgentMailer.success_notification
    # AgentMailer.success_notification(
    #   recipients: recipients,
    #   agent_name: @support_agent.name,
    #   entity_name: @entity.name,
    #   result: result
    # ).deliver_later

    Rails.logger.info("[AgentNotificationService] Would send success email to: #{recipients.join(', ')}")
    Rails.logger.info("[AgentNotificationService] Summary: #{result[:summary].inspect}")
  end

  # Sends in-app notification for success.
  #
  # @param recipients [Array<String>] email addresses (to find users)
  # @param result [Hash] execution result
  # @return [void]
  def send_success_in_app(recipients, _result)
    # TODO: Implement in-app notification
    # Users matching recipients could receive notifications like:
    # Notification.create!(
    #   user: user,
    #   notification_type: 'agent_success',
    #   title: "#{@support_agent.name} completed",
    #   message: "Processed #{result[:summary][:processed]} items for #{@entity.name}",
    #   ...
    # )

    Rails.logger.info("[AgentNotificationService] Would send in-app notification to #{recipients.count} user(s)")
  end

  # Sends error email to support team.
  #
  # @param errors [Array<Hash>] list of errors
  # @return [void]
  def send_error_email(errors)
    # TODO: Implement AgentMailer.error_notification
    # AgentMailer.error_notification(
    #   recipients: [support_email],
    #   agent_name: @support_agent.name,
    #   entity_name: @entity.name,
    #   errors: errors,
    #   execution_log: @execution_log
    # ).deliver_later

    Rails.logger.info("[AgentNotificationService] Would send error email to support")
    Rails.logger.info("[AgentNotificationService] Errors: #{errors.pluck(:error).join('; ')}")
  end

  # Returns the support email address.
  #
  # @return [String] support email
  def support_email
    Rails.configuration.try(:support_email) || ENV.fetch('SUPPORT_EMAIL', 'support@example.com')
  end
end
