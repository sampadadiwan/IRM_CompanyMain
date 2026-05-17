# frozen_string_literal: true

# Mailer for sending the consolidated deals fundraising report after a
# DealsReportAgent run. Flags deals needing attention in the subject line.
#
# @see DealsReportAgent
class DealsReportMailer < ApplicationMailer
  helper CurrencyHelper

  def send_report
    @support_agent = SupportAgent.find(params[:support_agent_id])
    @deal_results  = params[:deal_results]
    @recipients    = params[:recipients]
    @entity        = @support_agent.entity

    to_emails = Array(@recipients).join(",")

    needs_attention = @deal_results.any? { |d| d[:deal_status] == "needs_attention" }
    subject = if needs_attention
                "Deal Fundraising Update - #{Time.zone.today.strftime('%B %Y')} - Action Required"
              else
                "Deal Fundraising Update - #{Time.zone.today.strftime('%B %Y')}"
              end

    mail(to: to_emails, subject: subject)
  end
end
