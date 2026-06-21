# frozen_string_literal: true

# Sends a reminder email to notify_email when a DealActivity is overdue or
# approaching its due date. Invoked by DealManagementAgent#send_activity_reminders
# via deliver_later (ActiveJob).
#
# Params:
#   support_agent_id [Integer]
#   deal_id          [Integer]
#   deal_activity_id [Integer]
#   investor_name    [String]
#   notify_email     [String]  recipient address from agent config
#   days_until_due   [Integer] negative = overdue, 0 = due today, positive = upcoming
class DealManagementReminderMailer < SupportAgentBaseMailer
  def deal_activity_reminder
    @support_agent  = SupportAgent.find(params[:support_agent_id])
    @deal           = Deal.find(params[:deal_id])
    @activity       = DealActivity.find(params[:deal_activity_id])
    @investor_name  = params[:investor_name]
    @days_until_due = params[:days_until_due].to_i
    @notify_email   = params[:notify_email]
    @entity         = @support_agent.entity

    subject = if @days_until_due.negative?
                "Overdue Activity (#{@days_until_due.abs}d): #{@activity.title} — #{@investor_name}"
              elsif @days_until_due.zero?
                "Activity Due Today: #{@activity.title} — #{@investor_name}"
              else
                "Reminder (#{@days_until_due}d): #{@activity.title} — #{@investor_name}"
              end

    mail(to: @notify_email, subject: "[#{@deal.name}] #{subject}")
  end
end
