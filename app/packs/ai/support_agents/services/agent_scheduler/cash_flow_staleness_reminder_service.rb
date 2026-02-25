# frozen_string_literal: true

# Checks data freshness for upcoming CashFlowAssistantAgent runs and sends
# reminder emails to configured recipients when stale data is detected.
#
# Called daily from DailyMorningJob. For each active CashFlowAssistantAgent,
# checks if the next scheduled run is within the reminder window and emails
# recipients if any fund data is stale.
#
# @see CashFlowStalenessChecker
# @see CashFlowReminderMailer
class CashFlowStalenessReminderService
  def call
    SupportAgent.enabled
                .where(agent_type: "CashFlowAssistantAgent")
                .find_each { |agent| process_agent(agent) }
  end

  private

  def process_agent(support_agent)
    config          = support_agent.json_fields
    days_before_run = (config["reminder_days_before_run"] || 7).to_i
    recipients      = (config["reminder_recipients"] || "").split(",").map(&:strip).compact_blank

    return if recipients.empty?

    schedule = AgentSchedule.find_by(support_agent_id: support_agent.id, status: "active")
    return unless schedule&.next_run_at

    days_until_run = (schedule.next_run_at.to_date - Time.zone.today).to_i
    return unless days_until_run.between?(0, days_before_run)

    fund_statuses = CashFlowStalenessChecker.new(support_agent).check_all_funds

    CashFlowReminderMailer.with(
      support_agent_id: support_agent.id,
      fund_statuses: fund_statuses,
      recipients: recipients,
      days_until_run: days_until_run,
      next_run_at: schedule.next_run_at
    ).send_reminder.deliver_later
  rescue StandardError => e
    Rails.logger.error { "[CashFlowStalenessReminderService] Error for agent #{support_agent.id}: #{e.message}" }
  end
end
