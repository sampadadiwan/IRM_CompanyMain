# Notifier for Agent Scheduler execution notifications.
#
# Handles multi-channel delivery (email, WhatsApp, in-app) for agent
# execution outcomes using the Noticed gem pattern.
#
# @example Sending a failure notification
#   AgentSchedulerNotifier.with(
#     record: execution_log,
#     entity_id: entity.id,
#     email_method: :agent_failure,
#     user_id: user.id
#   ).deliver_later(user)
#
# @see BaseNotifier
# @see AgentSchedulerMailer
class AgentSchedulerNotifier < BaseNotifier
  required_param :email_method
  # Specifies the mailer class to use for email delivery.
  #
  # @param _notification [Noticed::Notification] the notification instance
  # @return [Class] the mailer class
  def mailer_name(_notification = nil)
    AgentSchedulerMailer
  end

  # Builds the data hash passed to the mailer.
  #
  # @param notification [Noticed::Notification] the notification instance
  # @return [Hash] data for the mailer
  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      execution_log_id: record.id,
      email_method: params[:email_method]
    }
  end

  # Notification methods define in-app message and URL.
  notification_methods do
    # Message shown in in-app notifications and WhatsApp.
    #
    # @return [String] the notification message
    def message
      @execution_log ||= record
      @agent ||= @execution_log.support_agent

      case params[:email_method].to_sym
      when :agent_success
        "#{@agent.name} completed successfully"
      when :agent_failure
        "#{@agent.name} failed and requires attention"
      when :agent_partial_success
        "#{@agent.name} completed with some errors"
      else
        "#{@agent.name} execution update"
      end
    end

    # URL for the notification link (in-app notifications).
    #
    # @return [String] the URL to view execution details
    def url
      @execution_log ||= record
      support_agent_agent_schedule_path(
        support_agent_id: @execution_log.support_agent_id,
        sub_domain: @execution_log.entity.sub_domain
      )
    end
  end
end
