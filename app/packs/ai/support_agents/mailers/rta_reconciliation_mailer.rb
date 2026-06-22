# frozen_string_literal: true

# Sends the RTA reconciliation summary email after each agent run.
#
# Triggered by RtaReconciliationAgent#send_reconciliation_report when
# send_report = "Yes" and notify_email is present.
class RtaReconciliationMailer < SupportAgentBaseMailer
  def reconciliation_report(support_agent, fund, ctx)
    @support_agent  = support_agent
    @fund           = fund
    @scheme_results = ctx[:scheme_results] || []
    @issues         = ctx[:issues] || []
    # Mirror the agent's formula: only :success/:blocking count toward health so the
    # emailed percentage matches the health_score saved in the report. :warning issues
    # (pending requests, reverse-check flags) are advisory and excluded from the denominator.
    active_issues   = @issues.select { |i| i[:severity].in?([:success, :blocking]) }
    @health_score   = active_issues.any? ? ((active_issues.count { |i| i[:severity] == :success }.to_f / active_issues.size) * 100).round : 100
    # Honour the statement_date override in json_fields before falling back to the extracted date.
    date_override   = support_agent.json_fields["statement_date"].to_s.strip
    @statement_date = date_override.presence || ctx[:extracted]&.dig(:statement_date)
    @amc            = ctx[:extracted]&.dig(:amc)

    breaks = @issues.count { |i| i[:severity] == :blocking }
    subject = breaks.positive? ? "[RTA BREAK] #{@fund.name} — #{breaks} break(s)" : "[RTA OK] #{@fund.name} — All matched"

    mail(to: support_agent.json_fields["notify_email"], subject: subject)
  end
end
