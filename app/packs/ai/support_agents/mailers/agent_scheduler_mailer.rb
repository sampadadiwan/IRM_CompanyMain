# Mailer for Agent Scheduler notifications.
#
# Sends email notifications about agent execution outcomes.
# Follows the same patterns as other Caphive mailers.
#
# @see AgentSchedulerNotifier
class AgentSchedulerMailer < ApplicationMailer
  helper ApplicationHelper

  before_action :set_execution_context

  # Notifies a user that an agent completed successfully.
  def agent_success
    subject = "[Agent Success] #{@agent.name} completed"
    send_mail(subject: subject)
  end

  # Notifies a user that an agent failed after all retries.
  def agent_failure
    subject = "[Agent Failed] #{@agent.name} requires attention"
    send_mail(subject: subject)
  end

  # Notifies a user that an agent had partial success.
  def agent_partial_success
    subject = "[Agent Warning] #{@agent.name} completed with errors"
    send_mail(subject: subject)
  end

  # Sends detailed error report to internal support team.
  # Contains technical details not shown to clients.
  def agent_error_internal
    @to = internal_support_email
    subject = "[AGENT ERROR] #{@agent.name} - #{@entity.name}"

    mail(
      from: @from || ENV.fetch("SUPPORT_EMAIL_FROM", nil),
      to: @to,
      subject: subject
    )
  end

  private

  # Sets up common instance variables from params.
  def set_execution_context
    @execution_log = AgentExecutionLog.find(params[:execution_log_id]) if params[:execution_log_id]
    return unless @execution_log

    @agent = @execution_log.support_agent
    @schedule = @execution_log.agent_schedule
    @set_execution_context ||= @execution_log.entity
  end

  # Returns the internal support email address.
  #
  # @return [String] support email address
  def internal_support_email
    ENV.fetch('INTERNAL_SUPPORT_EMAIL', 'support@caphive.com')
  end
end
