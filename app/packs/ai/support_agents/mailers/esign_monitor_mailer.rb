# frozen_string_literal: true

# Sends the E-Sign Monitor status report email to entity stakeholders.
#
# Triggered by EsignMonitorAgent#notify_stakeholders after both the pending and
# expired document scans have completed, so the email covers the full picture in
# one send.
#
# Recipients come from notify_tag in the agent's json_fields (employees with that
# tag), falling back to the entity's primary_email when no tag is configured.
#
# Params (passed via .with(...)):
#   entity_id         — loaded by ApplicationMailer#setup_defaults → @entity
#   support_agent_id  — used to link back to the agent page
#   pending_docs_data — Array of { name:, days_waiting:, pending_signers: [{email:, label:}] }
#   expired_issues    — Array of { name:, message: } from flag_expired_esigns issues
#   recipients        — Array<String> email addresses
class EsignMonitorMailer < SupportAgentBaseMailer
  def stuck_documents_report
    @support_agent  = SupportAgent.find(params[:support_agent_id])
    @pending_docs   = Array(params[:pending_docs_data])
    @expired_issues = Array(params[:expired_issues])
    recipients      = Array(params[:recipients]).compact

    to_emails = recipients.join(", ")

    subject = build_subject
    mail(to: to_emails, subject: subject)
  end

  private

  def build_subject
    p = @pending_docs.size
    e = @expired_issues.size
    entity_name = @entity&.name || ""

    if p > 0 && e > 0
      "[E-Sign Alert] #{p} pending + #{e} expired — #{entity_name}"
    elsif p > 0
      "[E-Sign Alert] #{p} document#{"s" if p != 1} awaiting signatures — #{entity_name}"
    else
      "[E-Sign Alert] #{e} expired document#{"s" if e != 1} need attention — #{entity_name}"
    end
  end
end
