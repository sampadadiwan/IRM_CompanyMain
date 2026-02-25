# frozen_string_literal: true

# Mailer for sending data staleness reminder emails before a scheduled
# CashFlowAssistantAgent run. Notifies recipients of which funds have
# stale data and how many days remain until the next run.
#
# @see CashFlowStalenessReminderService
class CashFlowReminderMailer < ApplicationMailer
  helper CurrencyHelper

  def send_reminder
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @fund_statuses = params[:fund_statuses]
    @recipients    = params[:recipients]
    @days_until_run = params[:days_until_run]
    @next_run_at   = params[:next_run_at]
    @entity        = @support_agent.entity

    to_emails = Array(@recipients).join(",")

    all_fresh = @fund_statuses.all? { |f| f[:status] == "ready" }

    subject = if all_fresh
                "Cash Flow Report - All Data Ready (#{@days_until_run} days to run)"
              else
                "Cash Flow Report - Data Update Required (#{@days_until_run} days to run)"
              end

    mail(to: to_emails, subject: subject)
  end
end
