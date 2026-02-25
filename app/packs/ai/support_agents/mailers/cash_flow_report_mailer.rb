# frozen_string_literal: true

# Mailer for sending the consolidated cash flow analysis report after a
# CashFlowAssistantAgent run. Highlights shortfall funds with an
# "Action Required" subject line.
#
# @see CashFlowAssistantAgent
class CashFlowReportMailer < ApplicationMailer
  helper CurrencyHelper

  def send_report
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @fund_results  = params[:fund_results]
    @recipients    = params[:recipients]
    @entity        = @support_agent.entity
    @currency      = @fund_results.find { |f| f[:currency] }&.dig(:currency) || "INR"

    to_emails = Array(@recipients).join(",")

    has_shortfall = @fund_results.any? { |f| f[:fund_status] == "shortfall" }
    subject = if has_shortfall
                "Cash Flow Update - #{Time.zone.today.strftime('%B %Y')} - Action Required"
              else
                "Cash Flow Update - #{Time.zone.today.strftime('%B %Y')}"
              end

    mail(to: to_emails, subject: subject)
  end
end
