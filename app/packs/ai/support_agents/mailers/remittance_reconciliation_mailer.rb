# frozen_string_literal: true

# Sends the capital remittance reconciliation summary email after each agent run.
#
# Triggered by RemittanceReconciliationAgent#send_reconciliation_report when
# send_report = "Yes" and notify_email is present. Mirrors RtaReconciliationMailer.
class RemittanceReconciliationMailer < SupportAgentBaseMailer
  def reconciliation_report(support_agent, capital_call, ctx)
    @support_agent = support_agent
    @capital_call  = capital_call
    @fund          = capital_call.fund
    @deposits      = ctx[:deposits] || []
    @issues        = ctx[:issues] || []
    @tier_counts   = ctx[:tier_counts] || {}
    @discrepancies = @deposits.select { |d| d["source_of_funds"] == "discrepancy" }
    @needs_review  = @deposits.select { |d| d["tier"] == "needs_review" }
    @no_match      = @deposits.select { |d| d["tier"] == "no_match" }
    @payments_created = ctx[:payments_created] || 0
    @auto_apply = support_agent.json_fields["auto_apply_exact"].to_s.casecmp("yes").zero?

    # A blocking issue means the run never got as far as scoring (no statement, unreadable
    # workbook) — say so in the subject rather than reporting "0 discrepancies" as if it ran.
    blocked = @issues.any? { |i| (i[:severity] || i["severity"]).to_s == "blocking" }
    subject =
      if blocked
        "[RECON BLOCKED] #{@fund.name} / #{capital_call.name} — run could not complete"
      elsif @discrepancies.any?
        "[RECON REVIEW] #{@fund.name} / #{capital_call.name} — #{@discrepancies.size} funding-source discrepancy(ies)"
      elsif @needs_review.any? || @no_match.any?
        "[RECON REVIEW] #{@fund.name} / #{capital_call.name} — #{@needs_review.size + @no_match.size} deposit(s) need attention"
      else
        "[RECON OK] #{@fund.name} / #{capital_call.name} — all deposits matched"
      end

    mail(to: support_agent.json_fields["notify_email"], subject: subject)
  end
end
