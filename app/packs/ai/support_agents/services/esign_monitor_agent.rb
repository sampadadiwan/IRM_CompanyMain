# frozen_string_literal: true

# Monitors the e-signing pipeline for stuck or expired documents.
#
# EsignMonitorAgent runs at the entity level. It finds documents in "requested"
# e-sign status that have been waiting longer than a configured threshold, flags
# expired/voided documents, and emails stakeholders with a full status report
# including which specific signers have not yet signed.
#
# json_fields configuration:
#   notify_tag          — employee tag for report recipients (e.g. "admin")
#   flag_expired        — "true"/"false" (default true) — surface expired/voided docs
#   reminder_after_days — integer (default 3) — days in "requested" before inclusion
#
# Note: no automatic resending is performed. The agent is an observer/notifier only.
# Manual resend must be done from the document page.
#
# @see SupportAgentService
class EsignMonitorAgent < SupportAgentService
  DESCRIPTION = "Monitors the e-signing pipeline: surfaces stuck requests and expired documents, then emails stakeholders with a full status report."

  LONG_DESCRIPTION = <<~DESC
    Monitors the e-signature pipeline and notifies stakeholders about stuck or expired documents.
    Targets the entity itself and scans documents where sent_for_esign is true (deliberately
    initiated through the e-sign workflow) — documents that were never sent for e-sign are excluded.

    Actions:
    • Find Pending — identifies documents stuck in "requested" state longer than reminder_after_days
      (default 3 days) that have at least one pending signatory.
    • Flag Expired — surfaces documents in expired, cancelled, or voided e-sign state for manual ops action.
      Controlled by flag_expired (true/false).
    • Notify Team — sends an email report to tagged employees (notify_tag) or the entity primary email,
      listing stuck documents with their pending signatories and expired documents that need manual attention.
      No documents are automatically resent — the email is the action.

    No LLM calls — entirely deterministic. Designed to run on a daily schedule. Results are saved
    as a SupportAgentReport listing each document with its status and pending signatories.

    Config: notify_tag (employee tag for recipients), flag_expired (true/false), reminder_after_days (integer)
  DESC

  STEP_LABELS = {
    initialize_agent:         "Initialize",
    find_pending_esigns:      "Find Pending",
    flag_expired_esigns:      "Flag Expired",
    notify_stakeholders:      "Notify Team",
    generate_progress_reports: "Save Report"
  }.freeze

  step :initialize_agent
  step :find_pending_esigns
  step :flag_expired_esigns
  step :notify_stakeholders
  step :generate_progress_reports

  def targets(entity_id)
    Entity.where(id: entity_id)
  end

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:entity] = target
    ctx[:issues] = { esign_issues: [] }
    ctx[:pending_docs] = []
    @support_agent.enabled?
  end

  # Queries documents in "requested" state that have been waiting too long
  # and have at least one e-signature recipient on file.
  def find_pending_esigns(ctx, target:, **)
    reminder_after_days = @support_agent.json_fields["reminder_after_days"]&.to_i || 3

    ctx[:pending_docs] = Document
                         .where(entity_id: target.id)
                         .sent_for_esign
                         .esign_status_requested
                         .where(updated_at: ...reminder_after_days.days.ago)
                         .joins(:e_signatures)
                         .where.not(e_signatures: { email: [nil, ""] })
                         .distinct
                         .includes(:e_signatures)

    count = ctx[:pending_docs].size
    ctx[:issues][:esign_issues] << {
      type: :info,
      message: "#{count} document(s) pending e-sign for more than #{reminder_after_days} day(s)",
      severity: count.positive? ? :warning : :success
    }
    Rails.logger.info { "[EsignMonitorAgent] Found #{count} stuck e-sign request(s) for entity #{target.id}" }
    true
  end

  # Surfaces documents with expired, cancelled, voided, or failed e-sign status.
  #
  # Configurable: flag_expired — "true"/"false"
  def flag_expired_esigns(ctx, target:, **)
    unless enabled?("flag_expired")
      ctx[:issues][:esign_issues] << {
        type: :info, message: "Expired document check skipped via configuration", severity: :success
      }
      Rails.logger.debug { "[EsignMonitorAgent] flag_expired disabled, skipping." }
      return true
    end

    flagged_docs = Document
                   .where(entity_id: target.id)
                   .sent_for_esign
                   .where(esign_status: %w[expired cancelled voided failed])
                   .joins(:e_signatures)
                   .where.not(e_signatures: { email: [nil, ""] })
                   .distinct

    flagged_docs.each do |doc|
      message = if doc.esign_status == "failed"
                  "E-sign failed — check provider logs and re-initiate manually"
                else
                  "E-sign #{doc.esign_status} — re-initiate manually from the document page"
                end

      ctx[:issues][:esign_issues] << {
        type: :expired, name: doc.name,
        message: message,
        severity: :blocking
      }
    end

    if flagged_docs.empty?
      ctx[:issues][:esign_issues] << {
        type: :info, message: "No expired, voided, or failed e-sign documents", severity: :success
      }
    end

    Rails.logger.info { "[EsignMonitorAgent] Found #{flagged_docs.size} expired/voided/failed e-sign document(s)" }
    true
  end

  # Builds per-document issue entries with signatory detail, then sends one
  # consolidated email to tagged employees (or entity primary_email).
  # Does not resend any documents — notification only.
  def notify_stakeholders(ctx, target:, **)
    pending_docs    = ctx[:pending_docs]
    expired_issues  = ctx[:issues][:esign_issues].select { |i| i[:type].to_s == "expired" }

    # Record per-document signatory detail for the report.
    # Filter in Ruby — e_signatures are already eager-loaded; calling a scope would re-query.
    pending_docs.each do |doc|
      pending_signers = doc.e_signatures.select { |s| s.email.present? && s.status != "signed" }
      signer_labels   = pending_signers.map { |s| s.label.presence || s.email }

      ctx[:issues][:esign_issues] << {
        type: :notified,
        name: doc.name,
        message: pending_signers.any? ? "Pending: #{signer_labels.join(', ')}" : "No signers identified",
        severity: :warning,
        pending_signers: pending_signers.map { |s| { email: s.email, label: s.label } }
      }
    end

    if pending_docs.empty? && expired_issues.empty?
      ctx[:issues][:esign_issues] << {
        type: :info, message: "Nothing to report — notification skipped", severity: :success
      }
      Rails.logger.info { "[EsignMonitorAgent] No issues found, skipping email." }
      return true
    end

    # Resolve recipients: notify_tag employees, fall back to entity primary_email
    notify_tag = @support_agent.json_fields["notify_tag"]
    recipients = if notify_tag.present?
                   target.employees.where(tag: notify_tag).pluck(:email).compact
                 else
                   [target.primary_email].compact
                 end

    if recipients.empty?
      ctx[:issues][:esign_issues] << {
        type: :info, message: "No recipients configured — set notify_tag in agent settings", severity: :warning
      }
      Rails.logger.warn { "[EsignMonitorAgent] No recipients for entity #{target.id}, skipping email." }
      return true
    end

    EsignMonitorMailer.with(
      entity_id:          target.id,
      support_agent_id:   @support_agent.id,
      pending_docs_data:  build_pending_docs_data(pending_docs),
      expired_issues:     expired_issues.map { |i| { name: i[:name], message: i[:message] } },
      recipients:         recipients
    ).stuck_documents_report.deliver_later

    ctx[:issues][:esign_issues] << {
      type: :info,
      message: "Status report emailed to #{recipients.join(', ')}",
      severity: :success
    }
    Rails.logger.info { "[EsignMonitorAgent] Status report emailed to #{recipients.join(', ')}" }
    true
  end

  def generate_progress_reports(ctx, target:, support_agent:, **)
    super(ctx, model: target, support_agent: support_agent)
  end

  # Serialises pending documents into a plain-hash structure safe to pass as mailer params.
  # Filters in Ruby — e_signatures are already eager-loaded by find_pending_esigns.
  def build_pending_docs_data(docs)
    docs.map do |doc|
      pending_signers = doc.e_signatures.select { |s| s.email.present? && s.status != "signed" }
      {
        name:            doc.name,
        days_waiting:    ((Time.current - doc.updated_at) / 1.day).floor,
        pending_signers: pending_signers.map { |s| { email: s.email, label: s.label } }
      }
    end
  end
end
